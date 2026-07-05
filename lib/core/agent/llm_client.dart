import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';

/// Gemini API istemcisi (function calling destekli).
///
/// generateContent endpoint'ini kullanir. Modelin donusu ya duz metin,
/// ya da bir/birden fazla functionCall icerir.
class LlmClient {
  final String apiKey;
  final String model;

  LlmClient({
    required this.apiKey,
    this.model = 'gemini-2.0-flash',
  });

  Uri get _endpoint => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent?key=$apiKey',
      );

  /// Bir tur konusma yapar.
  ///
  /// [history] tum sohbet gecmisi (system haric).
  /// [systemPrompt] ajan davranis talimati.
  /// [toolDeclarations] araclarin Gemini semasi.
  ///
  /// Donen ChatMessage ya text tasir ya da toolCalls tasir.
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) async {
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': _toContents(history),
      'tools': [
        {'functionDeclarations': toolDeclarations}
      ],
      'generationConfig': {
        'temperature': 0.4,
      },
    };

    final res = await http.post(
      _endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      return ChatMessage(
        role: Role.assistant,
        text: 'API HATASI ${res.statusCode}: ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _parseResponse(data);
  }

  /// Sohbet gecmisini Gemini "contents" formatina cevirir.
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
    final parts =
        (candidates.first['content']?['parts'] as List?) ?? const [];

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
