import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../log/app_log.dart';
import '../settings.dart';

/// flutter_gemma (MediaPipe) ile offline model motoru. flutter_gemma API'sine
/// dokunan TEK yer burasi; boylece surum degisiklikleri tek noktada yonetilir.
class GemmaEngine {
  static const _kInstalled = 'gemma_installed';
  bool _initialized = false;
  String? _initedToken;
  dynamic _model;

  /// Onerilen offline model (LiteRT .task, HuggingFace).
  static const recommendedUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q8_ekv1280.task';

  Future<void> _ensureInit() async {
    final s = await AppSettings.load();
    final token = s.hfToken.trim().isEmpty ? null : s.hfToken.trim();
    // Token degistiyse motoru YENIDEN baslat (onceki token'siz init'e takilma).
    if (_initialized && _initedToken == token) return;
    AppLog.i('gemma init: token ${token == null ? "YOK" : "var(${token.length})"}');
    try {
      await FlutterGemma.initialize(
        inferenceEngines: [MediaPipeEngine()],
        huggingFaceToken: token,
      );
    } catch (e) {
      AppLog.e('gemma initialize hatasi: $e');
    }
    _initialized = true;
    _initedToken = token;
  }

  Future<bool> isInstalled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kInstalled) ?? false;
  }

  Future<void> _setInstalled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kInstalled, v);
  }

  /// Modeli agdan indirip kurar. [url] verilmezse onerilen kullanilir.
  /// Basarili ise null; hata varsa hata mesaji doner (arayuzde gosterilir).
  Future<String?> install({
    String? url,
    required void Function(double) onProgress,
  }) async {
    final target = (url == null || url.trim().isEmpty) ? recommendedUrl : url.trim();
    try {
      await _ensureInit();
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(target)
          .withProgress((p) {
        final v = (p is num) ? p.toDouble() : 0.0;
        onProgress(v > 1 ? v / 100.0 : v);
      }).install();
      await _setInstalled(true);
      return null;
    } catch (e) {
      return e.toString();
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
