import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent/llm_client.dart';
import '../settings.dart';
import 'tool.dart';

const _ua =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0 Mobile Safari/537.36';

/// HTML etiketlerini temizler ve bosluklari sadelestirir.
String _stripHtml(String s) {
  var out = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
  out = out
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Internette arama. Once Gemini'nin SUNUCU TARAFI Google aramasini (grounding)
/// dener (kaliteli/guncel); Gemini anahtari yoksa anahtarsiz DuckDuckGo'ya duser.
class WebSearchTool extends Tool {
  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Internette GUNCEL bilgi arar (Google tabanli). Haber, fiyat, hava '
      'durumu, "nedir/kimdir", son gelismeler gibi guncel olabilecek her seyde '
      'tahmin etme, BUNU kullan. Kaynak adresleriyle birlikte ozet doner; '
      'daha fazla detay icin bir adresi fetch_url ile acabilirsin.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Arama sorgusu.'},
        },
        'required': ['query'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final q = (args['query'] ?? '').toString().trim();
    if (q.isEmpty) return 'HATA: bos sorgu.';

    // 1) Gemini sunucu tarafi Google aramasi (grounding).
    final grounded = await _geminiGrounded(q);
    if (grounded.isNotEmpty) return grounded;

    // 2) Yedek: anahtarsiz DuckDuckGo.
    try {
      final res = await http
          .post(
            Uri.parse('https://html.duckduckgo.com/html/'),
            headers: {
              'User-Agent': _ua,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'q': q},
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        return 'Arama basarisiz (HTTP ${res.statusCode}).';
      }
      final body = res.body;
      final linkRe = RegExp(
          r'result__a"[^>]*href="(.*?)".*?>(.*?)</a>',
          dotAll: true);
      final snipRe = RegExp(
          r'result__snippet"[^>]*>(.*?)</a>',
          dotAll: true);
      final links = linkRe.allMatches(body).toList();
      final snips = snipRe.allMatches(body).toList();
      if (links.isEmpty) return 'Sonuc bulunamadi: $q';

      final sb = StringBuffer();
      final n = links.length < 6 ? links.length : 6;
      for (var i = 0; i < n; i++) {
        final url = _cleanDdgUrl(links[i].group(1) ?? '');
        final title = _stripHtml(links[i].group(2) ?? '');
        final snippet =
            i < snips.length ? _stripHtml(snips[i].group(1) ?? '') : '';
        sb.writeln('${i + 1}. $title');
        sb.writeln('   $url');
        if (snippet.isNotEmpty) sb.writeln('   $snippet');
      }
      return sb.toString().trim();
    } catch (e) {
      return 'Arama hatasi: $e';
    }
  }

  /// Gemini'nin sunucu tarafi Google aramasi (grounding) ile guncel yanit +
  /// kaynaklar. Ayri bir istek oldugu icin ana ajanin araclariyla cakismaz.
  Future<String> _geminiGrounded(String query) async {
    try {
      final s = await AppSettings.load();
      final key = s.apiKeys[LlmProvider.gemini] ?? '';
      if (key.trim().isEmpty) return '';
      var model = s.models[LlmProvider.gemini] ?? '';
      if (model.trim().isEmpty) model = 'gemini-2.5-flash';

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$model:generateContent?key=$key');
      final body = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': query}
            ]
          }
        ],
        'tools': [
          {'google_search': <String, dynamic>{}}
        ],
        'generationConfig': {'temperature': 0.2},
      });
      final res = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) return '';
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final cands = data['candidates'] as List?;
      if (cands == null || cands.isEmpty) return '';
      final cand = cands.first as Map;
      final parts = (cand['content']?['parts'] as List?) ?? const [];
      final sb = StringBuffer();
      for (final p in parts) {
        if (p is Map && p['text'] != null) sb.write(p['text']);
      }
      var out = sb.toString().trim();
      if (out.isEmpty) return '';
      // Kaynaklari ekle (grounding metadata).
      final gm = cand['groundingMetadata'] as Map?;
      final chunks = gm?['groundingChunks'] as List?;
      if (chunks != null && chunks.isNotEmpty) {
        final srcs = StringBuffer('\n\nKaynaklar:');
        var n = 0;
        for (final c in chunks) {
          if (n >= 5) break;
          final web = (c as Map)['web'] as Map?;
          if (web != null) {
            srcs.write('\n- ${web['title'] ?? ''}: ${web['uri'] ?? ''}');
            n++;
          }
        }
        if (n > 0) out += srcs.toString();
      }
      return out;
    } catch (_) {
      return '';
    }
  }

  /// DDG yonlendirme linkinden (//duckduckgo.com/l/?uddg=...) gercek URL'yi cikarir.
  String _cleanDdgUrl(String raw) {
    var u = raw;
    if (u.startsWith('//')) u = 'https:$u';
    final m = RegExp(r'[?&]uddg=([^&]+)').firstMatch(u);
    if (m != null) {
      try {
        return Uri.decodeComponent(m.group(1)!);
      } catch (_) {}
    }
    return u;
  }
}

/// Bir web sayfasini indirir ve okunabilir metnini dondurur.
class FetchUrlTool extends Tool {
  @override
  String get name => 'fetch_url';

  @override
  String get description =>
      'Verilen web adresini indirir ve sayfanin okunabilir METIN icerigini '
      'dondurur (HTML temizlenir). web_search sonuclarindaki bir sayfayi '
      'detayli okumak veya bir API/JSON adresini almak icin kullan.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'Okunacak adres (https://...).'},
        },
        'required': ['url'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    var url = (args['url'] ?? '').toString().trim();
    if (url.isEmpty) return 'HATA: bos url.';
    if (!url.startsWith('http')) url = 'https://$url';
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        return 'Sayfa alinamadi (HTTP ${res.statusCode}).';
      }
      final ctype = res.headers['content-type'] ?? '';
      var text = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (ctype.contains('json') ||
          text.trimLeft().startsWith('{') ||
          text.trimLeft().startsWith('[')) {
        // JSON ise oldugu gibi dondur (kirparak).
        return text.length > 4000 ? '${text.substring(0, 4000)}\n...(kesildi)' : text;
      }
      // HTML -> metin. Once script/style bloklarini at.
      text = text
          .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
      final clean = _stripHtml(text);
      if (clean.isEmpty) return '(sayfada okunabilir metin yok)';
      return clean.length > 4000
          ? '${clean.substring(0, 4000)}\n...(kesildi)'
          : clean;
    } catch (e) {
      return 'Sayfa okuma hatasi: $e';
    }
  }
}
