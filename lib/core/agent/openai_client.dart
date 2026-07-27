import 'dart:convert';

import '../../models/chat_message.dart';
import 'llm_client.dart';

/// OpenAI (GPT) Chat Completions istemcisi (tool calling).
class OpenAiClient extends LlmClient {
  OpenAiClient({
    required String apiKey,
    String model = 'gpt-4o-mini',
    int maxRetries = 3,
  }) : super(apiKey: apiKey, model: model, maxRetries: maxRetries);

  final Uri _endpoint = Uri.parse('https://api.openai.com/v1/chat/completions');

  @override
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) {
    final tools = toolDeclarations
        .map((d) => {
              'type': 'function',
              'function': {
                'name': d['name'],
                'description': d['description'],
                'parameters': d['parameters'],
              },
            })
        .toList();

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ..._toMessages(history),
    ];

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'tools': tools,
      'temperature': 0.4,
    });

    return HttpRetry.post(
      url: _endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
      maxRetries: maxRetries,
      parse: _parseResponse,
    );
  }

  List<Map<String, dynamic>> _toMessages(List<ChatMessage> history) {
    final out = <Map<String, dynamic>>[];
    for (final m in history) {
      switch (m.role) {
        case Role.user:
          out.add({'role': 'user', 'content': m.text});
          break;
        case Role.assistant:
          final msg = <String, dynamic>{'role': 'assistant'};
          msg['content'] = m.text.isEmpty ? null : m.text;
          if (m.toolCalls.isNotEmpty) {
            msg['tool_calls'] = m.toolCalls
                .map((c) => {
                      'id': c.id,
                      'type': 'function',
                      'function': {
                        'name': c.name,
                        'arguments': jsonEncode(c.args),
                      },
                    })
                .toList();
          }
          out.add(msg);
          break;
        case Role.tool:
          final r = m.toolResult!;
          out.add({
            'role': 'tool',
            'tool_call_id': r.callId,
            'content': r.output,
          });
          // OpenAI arac mesajinda gorsel kabul etmez; gorseli takip eden bir
          // user mesajinda ilet.
          if (r.imageB64 != null && r.imageB64!.isNotEmpty) {
            out.add({
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'Ekran goruntusu:'},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,${r.imageB64}'
                  }
                }
              ]
            });
          }
          break;
        case Role.system:
          break;
      }
    }
    return out;
  }

  ChatMessage _parseResponse(Map<String, dynamic> data) {
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      return ChatMessage(role: Role.assistant, text: '(bos yanit)');
    }
    final msg = choices.first['message'] as Map? ?? const {};
    final text = (msg['content'] ?? '').toString();
    final calls = <ToolCall>[];
    final tc = msg['tool_calls'] as List?;
    if (tc != null) {
      for (final c in tc) {
        if (c is! Map) continue;
        final fn = c['function'] as Map? ?? const {};
        Map<String, dynamic> args = {};
        try {
          final raw = (fn['arguments'] ?? '{}').toString();
          args = raw.isEmpty
              ? {}
              : Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {}
        calls.add(ToolCall(
          id: (c['id'] ?? 'call_${calls.length}').toString(),
          name: (fn['name'] ?? '').toString(),
          args: args,
        ));
      }
    }
    return ChatMessage(
      role: Role.assistant,
      text: text.trim(),
      toolCalls: calls,
    );
  }
}
