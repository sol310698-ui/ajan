import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';

/// Gemini API istemcisi (function calling + otomatik yeniden deneme).
///
/// Telefon uykuya girince veya ag anlik koparsa istek dusebilir; bu durumda
/// birkac kez otomatik tekrar dener, boylece kullaniciya hata yansimaz.
class LlmClient {
  final String apiKey;
  final String model;
  final int maxRetries;

  LlmClient({
    required this.apiKey,
    this.model = 'gemini-2.5-flash',
    this.maxRetries = 3,
  });

  Uri get _endpoint => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent?key=$apiKey',
      );

  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) async {
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': _toContents(history),
      'tools': [
        {'functionDeclarations': toolDeclarations}
      ],
      'generationConfig': {'temperature': 0.4},
    });

    Object? lastErr;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final res = await http
            .post(_endpoint,
                headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 45));

        // 5xx / 429 -> gecici, tekrar denemeye deger.
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
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return _parseResponse(data);
      } on SocketException catch (e) {
        // Ag kopmasi / uyku -> tekrar dene.
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

  Future<void> _backoff(int attempt) async {
    // 0.8s, 1.6s, 3.2s ...
    final ms = (800 * (1 << attempt)).clamp(800, 6000);
    await Future.delayed(Duration(milliseconds: ms));
  }

  List<Map<String, dynamic>> _toContents(List<ChatMessage> history) {
    final out = <Map<String, dynamic>>[];
    for (final m in history) {
      switch (m.role) {
        case Role.user:
          out.add({
            'role': 'user',
            'parts': [
              {'text': m.text}
            ]
          });
          break;
        case Role.assistant:
          final parts = <Map<String, dynamic>>[];
          if (m.text.isNotEmpty) parts.add({'text': m.text});
          for (final c in m.toolCalls) {
            parts.add({
              'functionCall': {'name': c.name, 'args': c.args}
            });
          }
          if (parts.isNotEmpty) out.add({'role': 'model', 'parts': parts});
          break;
        case Role.tool:
          final r = m.toolResult!;
          out.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': r.name,
                  'response': {'result': r.output},
                }
              }
            ]
          });
          break;
        case Role.system:
          break;
      }
    }
    return out;
  }

  ChatMessage _parseResponse(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return ChatMessage(role: Role.assistant, text: '(bos yanit)');
    }
    final parts = (candidates.first['content']?['parts'] as List?) ?? const [];
    final buffer = StringBuffer();
    final calls = <ToolCall>[];
    var callIndex = 0;

    for (final p in parts) {
      if (p is! Map) continue;
      if (p['text'] != null) buffer.write(p['text']);
      if (p['functionCall'] != null) {
        final fc = p['functionCall'] as Map;
        calls.add(ToolCall(
          id: 'call_${callIndex++}',
          name: (fc['name'] ?? '').toString(),
          args: Map<String, dynamic>.from(fc['args'] ?? {}),
        ));
      }
    }
    return ChatMessage(
      role: Role.assistant,
      text: buffer.toString().trim(),
      toolCalls: calls,
    );
  }
}
