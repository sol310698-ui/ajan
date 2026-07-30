import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../log/app_log.dart';
import '../settings.dart';

/// Indirilebilir cihaz-ici model (LiteRT .task/.litertlm).
class LiteRtModel {
  final String id; // ornek: litert-community/Gemma3-1B-IT
  final String fileName;
  final String url;
  final int sizeMb;
  const LiteRtModel({
    required this.id,
    required this.fileName,
    required this.url,
    required this.sizeMb,
  });
  String get name => id.contains('/') ? id.split('/').last : id;
}

/// flutter_gemma (MediaPipe) ile offline model motoru. flutter_gemma API'sine
/// dokunan TEK yer burasi; boylece surum degisiklikleri tek noktada yonetilir.
class GemmaEngine {
  static const _kInstalled = 'gemma_installed';
  static const _kActiveName = 'gemma_active_name';
  bool _initialized = false;
  String? _initedToken;
  dynamic _model;

  /// HuggingFace'ten cihaz-ici (LiteRT) modelleri listeler (token'la).
  /// litert-community deposundaki .task/.litertlm dosyali modelleri getirir.
  Future<List<LiteRtModel>> listDownloadable() async {
    final s = await AppSettings.load();
    final token = s.hfToken.trim();
    final headers = <String, String>{
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    try {
      final res = await http.get(
        Uri.parse('https://huggingface.co/api/models'
            '?author=litert-community&full=true&limit=100'),
        headers: headers,
      ).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        AppLog.e('model listesi HTTP ${res.statusCode}');
        return [];
      }
      final list = jsonDecode(res.body) as List;
      final out = <LiteRtModel>[];
      for (final m in list) {
        if (m is! Map) continue;
        final id = (m['id'] ?? m['modelId'] ?? '').toString();
        final siblings = (m['siblings'] as List?) ?? const [];
        for (final sib in siblings) {
          final f = (sib is Map ? sib['rfilename'] : '').toString();
          // Yalnizca Android .task (web-only '-web.task' haric). Bu surumde
          // .litertlm yerel yuklemede yanlis motora gidiyor, onu sunmuyoruz.
          if (f.endsWith('.task') && !f.contains('-web')) {
            final size = (sib is Map && sib['size'] is num)
                ? ((sib['size'] as num) / (1024 * 1024)).round()
                : 0;
            out.add(LiteRtModel(
              id: id,
              fileName: f,
              url: 'https://huggingface.co/$id/resolve/main/$f',
              sizeMb: size,
            ));
            break; // her modelden ilk uygun dosya yeterli
          }
        }
      }
      out.sort((a, b) => a.sizeMb.compareTo(b.sizeMb));
      return out;
    } catch (e) {
      AppLog.e('model listesi hatasi: $e');
      return [];
    }
  }

  Future<String> activeName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActiveName) ?? '';
  }

  /// Onerilen offline model (LiteRT .task, HuggingFace).
  static const recommendedUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q8_ekv1280.task';

  /// Her iki motoru da kaydeder (MediaPipe .task/.bin, LiteRtLm .litertlm).
  /// Not: bu surumde .litertlm YEREL dosyalari yanlis motora yonlendiriliyor,
  /// bu yuzden listede yalnizca .task modelleri sunuyoruz.
  Future<void> _ensureInit({String? forFile}) async {
    final s = await AppSettings.load();
    final token = s.hfToken.trim().isEmpty ? null : s.hfToken.trim();
    if (_initialized && _initedToken == token) return;
    AppLog.i('gemma init: token '
        '${token == null ? "YOK" : "var(${token.length})"}');
    try {
      await FlutterGemma.initialize(
        inferenceEngines: [MediaPipeEngine(), LiteRtLmEngine()],
        huggingFaceToken: token,
      );
    } catch (e) {
      AppLog.e('gemma initialize hatasi: $e');
    }
    _initialized = true;
    _initedToken = token;
    _model = null;
  }

  Future<bool> isInstalled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kInstalled) ?? false;
  }

  Future<void> _setInstalled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kInstalled, v);
  }

  /// Modeli kurar. flutter_gemma'nin ag indiricisi HF token'ini gonderMEDIGI
  /// icin (gated modellerde 401), dosyayi KENDIMIZ token'la indirip yerel
  /// dosyadan kuruyoruz. Basarili ise null; hata varsa mesaj doner.
  Future<String?> install({
    String? url,
    String? name,
    required void Function(double) onProgress,
  }) async {
    final target =
        (url == null || url.trim().isEmpty) ? recommendedUrl : url.trim();
    try {
      final s = await AppSettings.load();
      AppLog.i('gemma.install: indiriliyor $target');
      final localPath = await _downloadWithToken(
        target,
        s.hfToken.trim(),
        onProgress,
      );
      // Indirilen dosyanin uzantisina gore DOGRU motoru kaydet.
      await _ensureInit(forFile: localPath);
      AppLog.i('gemma.install: yerel dosyadan kuruluyor');
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(localPath)
          .install();
      await _setInstalled(true);
      final p = await SharedPreferences.getInstance();
      await p.setString(_kActiveName, name ?? target.split('/').last);
      _model = null; // yeni model bir sonraki ask'te yuklensin
      AppLog.i('gemma.install: tamam');
      return null;
    } catch (e) {
      AppLog.e('gemma.install HATA: $e');
      return e.toString();
    }
  }

  /// Modeli HF token'i ile (Authorization header) indirip yerel yola yazar.
  Future<String> _downloadWithToken(
    String url,
    String token,
    void Function(double) onProgress,
  ) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    final fileName = url.split('/').last.split('?').first;
    final file = File('${dir.path}/$fileName');

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw 'indirme HTTP ${res.statusCode} (token/lisans?)';
      }
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      return file.path;
    } finally {
      client.close();
    }
  }

  /// Sohbet turlarini modele verip yaniti dondurur.
  Future<String> ask(String system, List<GemmaTurn> turns) async {
    try {
      AppLog.i('gemma.ask: init basliyor');
      await _ensureInit();
      // GPU (OpenCL) bazi cihazlarda modeli acamiyor; once GPU dene, olmazsa
      // CPU'ya dus (daha yavas ama her cihazda calisir).
      if (_model == null) {
        try {
          AppLog.i('gemma.ask: GPU model aciliyor');
          _model = await FlutterGemma.getActiveModel(
            maxTokens: 512,
            preferredBackend: PreferredBackend.gpu,
          );
          AppLog.i('gemma.ask: GPU model acildi');
        } catch (e) {
          AppLog.e('gemma.ask: GPU basarisiz ($e); CPU deneniyor');
          _model = await FlutterGemma.getActiveModel(
            maxTokens: 512,
            preferredBackend: PreferredBackend.cpu,
          );
          AppLog.i('gemma.ask: CPU model acildi');
        }
      }
      AppLog.i('gemma.ask: chat olusturuluyor (${turns.length} tur)');
      final chat = await _model.createChat(systemInstruction: system);
      for (final t in turns) {
        await chat.addQueryChunk(Message.text(text: t.text, isUser: t.isUser));
      }
      AppLog.i('gemma.ask: generate basliyor');
      final res = await chat.generateChatResponse();
      final out = res.toString().trim();
      AppLog.i('gemma.ask: yanit alindi (len=${out.length})');
      return out;
    } catch (e) {
      _model = null; // sonraki denemede yeniden kurulsun (CPU'ya dusebilsin)
      AppLog.e('gemma.ask HATA: $e');
      return 'Yerel model hatasi: $e';
    }
  }
}

class GemmaTurn {
  final String text;
  final bool isUser;
  const GemmaTurn(this.text, this.isUser);
}

/// Uygulama boyunca tek ornek.
final gemmaEngine = GemmaEngine();
