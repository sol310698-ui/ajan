import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import 'anthropic_client.dart';
import 'gemini_client.dart';
import 'openai_client.dart';

/// Desteklenen LLM saglayicilari.
enum LlmProvider { gemini, openai, anthropic }

extension LlmProviderX on LlmProvider {
  String get id => name;

  String get label {
    switch (this) {
      case LlmProvider.gemini:
        return 'Google Gemini';
      case LlmProvider.openai:
        return 'OpenAI (GPT)';
      case LlmProvider.anthropic:
        return 'Anthropic (Claude)';
    }
  }

  /// Ayarlarda onerilen varsayilan model.
  String get defaultModel {
    switch (this) {
      case LlmProvider.gemini:
        return 'gemini-2.5-flash';
      case LlmProvider.openai:
        return 'gpt-4o-mini';
      case LlmProvider.anthropic:
        return 'claude-3-5-sonnet-latest';
    }
  }

  /// API anahtarinin nereden alinacagina dair ipucu.
  String get keyHint {
    switch (this) {
      case LlmProvider.gemini:
        return 'AIza... (aistudio.google.com)';
      case LlmProvider.openai:
        return 'sk-... (platform.openai.com)';
      case LlmProvider.anthropic:
        return 'sk-ant-... (console.anthropic.com)';
    }
  }

  static LlmProvider fromId(String? id) => LlmProvider.values.firstWhere(
        (p) => p.name == id,
        orElse: () => LlmProvider.gemini,
      );
}

/// Tum saglayicilar icin ortak istemci arayuzu.
///
/// Ajan dongusu (AgentLoop) sadece bu arayuzu bilir; hangi saglayici oldugu
/// onemsizdir. Yeni saglayici = yeni bir alt sinif + factory'ye bir satir.
abstract class LlmClient {
  final String apiKey;
  final String model;
  final int maxRetries;

  LlmClient({
    required this.apiKey,
    required this.model,
    this.maxRetries = 3,
  });

  /// Gecmisi + sistem talimati + arac tanimlariyla modeli cagirir; modelin
  /// cevabini (duz metin ve/veya arac cagrilari) ChatMessage olarak dondurur.
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  });

  /// Saglayici + anahtar + modele gore dogru istemciyi uretir.
  static LlmClient create({
    required LlmProvider provider,
    required String apiKey,
    required String model,
    bool googleSearch = false,
  }) {
    final m = model.trim().isEmpty ? provider.defaultModel : model.trim();
    switch (provider) {
      case LlmProvider.gemini:
        return GeminiClient(apiKey: apiKey, model: m, googleSearch: googleSearch);
      case LlmProvider.openai:
        return OpenAiClient(apiKey: apiKey, model: m);
      case LlmProvider.anthropic:
        return AnthropicClient(apiKey: apiKey, model: m);
    }
  }
}

/// Saglayicilarin paylastigi HTTP + yeniden deneme yardimcisi.
///
/// Telefon uykuya girince veya ag anlik koparsa istek dusebilir; bu durumda
/// birkac kez otomatik tekrar dener, boylece kullaniciya hata yansimaz.
class HttpRetry {
  /// [ok] geldiginde govdeyi ChatMessage'a cevirmek [parse] ile yapilir.
  /// 5xx/429 ve ag hatalari geri cekilerek tekrar denenir.
  static Future<ChatMessage> post({
    required Uri url,
    required Map<String, String> headers,
    required String body,
    required int maxRetries,
    required ChatMessage Function(Map<String, dynamic> data) parse,
  }) async {
    Object? lastErr;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final res = await http
            .post(url, headers: headers, body: body)
            .timeout(const Duration(seconds: 60));

        if (res.statusCode >= 500 || res.statusCode == 429) {
          lastErr = 'API ${res.statusCode}';
          await _backoff(attempt);
          continue;
        }
        if (res.statusCode != 200) {
          return ChatMessage(
            role: Role.assistant,
            text: 'API HATASI ${res.statusCode}: ${res.body}',
          );
        }
        return parse(jsonDecode(res.body) as Map<String, dynamic>);
      } on SocketException catch (e) {
        lastErr = e;
        await _backoff(attempt);
      } on HttpException catch (e) {
        lastErr = e;
        await _backoff(attempt);
      } on IOException catch (e) {
        lastErr = e;
        await _backoff(attempt);
      }
    }
    return ChatMessage(
      role: Role.assistant,
      text: 'Baglanti kurulamadi ($maxRetries deneme). '
          'Internet dusuk gorunuyor, birazdan tekrar dene. [$lastErr]',
    );
  }

  static Future<void> _backoff(int attempt) async {
    final ms = (800 * (1 << attempt)).clamp(800, 6000);
    await Future.delayed(Duration(milliseconds: ms));
  }
}
