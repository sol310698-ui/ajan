import 'dart:convert';

import 'package:http/http.dart' as http;

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

/// Internette arama yapar (anahtarsiz; DuckDuckGo web sonuclari).
class WebSearchTool extends Tool {
  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Internette arama yapar ve en iyi sonuclari (baslik, adres, ozet) '
      'dondurur. Guncel bilgi, haber, fiyat, "nedir/kimdir", arastirma gibi '
      'seyler icin kullan. Detay gerekiyorsa donen adreslerden birini '
      'fetch_url ile ac ve icerigini oku.';

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
