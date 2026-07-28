import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import 'llm_client.dart';

/// Google Gemini API istemcisi (function calling).
class GeminiClient extends LlmClient {
  /// Google'in sunucu tarafi arama araci (grounding). Acikken model cevabini
  /// gercek zamanli Google aramasiyla destekler.
  final bool googleSearch;

  GeminiClient({
    required String apiKey,
    String model = 'gemini-2.5-flash',
    int maxRetries = 3,
    this.googleSearch = false,
  }) : super(apiKey: apiKey, model: model, maxRetries: maxRetries);

  Uri get _endpoint => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent?key=$apiKey',
      );

  @override
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) {
    // Gemini, built-in google_search ile function calling'i AYNI istekte
    // kabul etmez (400). Bu yuzden ya biri ya oteki:
    //  - googleSearch acik -> sadece Google aramali (grounded) yanit modu.
    //  - kapali -> tam ajan (fonksiyon araclari + web_search).
    final List<Map<String, dynamic>> tools = googleSearch
        ? [
            {'google_search': <String, dynamic>{}}
          ]
        : [
            {'functionDeclarations': toolDeclarations}
          ];

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': _toContents(history),
      'tools': tools,
      'generationConfig': {'temperature': 0.4},
    });

    return HttpRetry.post(
      url: _endpoint,
      headers: {'Content-Type': 'application/json'},
      body: body,
      maxRetries: maxRetries,
      parse: _parseResponse,
    );
  }

  @override
  Future<List<String>> listModels() async {
    try {
      final res = await http.get(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models'
            '?key=$apiKey&pageSize=1000'),
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final models = (data['models'] as List?) ?? const [];
      final out = <String>[];
      for (final m in models) {
        if (m is! Map) continue;
        final methods =
            (m['supportedGenerationMethods'] as List?)?.cast<String>() ??
                const [];
        if (!methods.contains('generateContent')) continue;
        final name = (m['name'] ?? '').toString();
        out.add(name.startsWith('models/') ? name.substring(7) : name);
      }
      out.sort();
      return out;
    } catch (_) {
      return const [];
    }
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
          final parts = <Map<String, dynamic>>[
            {
              'functionResponse': {
                'name': r.name,
                'response': {'result': r.output},
              }
            }
          ];
          // Arac gorsel urettiyse ayni user icerigine gorseli de ekle.
          if (r.imageB64 != null && r.imageB64!.isNotEmpty) {
            parts.add({
              'inlineData': {'mimeType': 'image/jpeg', 'data': r.imageB64}
            });
          }
          out.add({'role': 'user', 'parts': parts});
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
