import 'dart:convert';

import '../../models/chat_message.dart';
import 'llm_client.dart';

/// Anthropic (Claude) Messages API istemcisi (tool use).
class AnthropicClient extends LlmClient {
  AnthropicClient({
    required String apiKey,
    String model = 'claude-3-5-sonnet-latest',
    int maxRetries = 3,
  }) : super(apiKey: apiKey, model: model, maxRetries: maxRetries);

  final Uri _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  @override
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) {
    final tools = toolDeclarations
        .map((d) => {
              'name': d['name'],
              'description': d['description'],
              'input_schema': d['parameters'],
            })
        .toList();

    final body = jsonEncode({
      'model': model,
      'max_tokens': 4096,
      'system': systemPrompt,
      'messages': _toMessages(history),
      'tools': tools,
      'temperature': 0.4,
    });

    return HttpRetry.post(
      url: _endpoint,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: body,
      maxRetries: maxRetries,
      parse: _parseResponse,
    );
  }

  /// Claude rollerin (user/assistant) donusumlu olmasini ister. Bizim
  /// gecmiste ardil arac sonuclari (tool rolu) user turu sayilir; ardil ayni
  /// rolleri tek turda birlestiririz.
  List<Map<String, dynamic>> _toMessages(List<ChatMessage> history) {
    final turns = <Map<String, dynamic>>[]; // {role, blocks:[]}
    void push(String role, List<Map<String, dynamic>> blocks) {
      if (blocks.isEmpty) return;
      if (turns.isNotEmpty && turns.last['role'] == role) {
        (turns.last['content'] as List).addAll(blocks);
      } else {
        turns.add({'role': role, 'content': [...blocks]});
      }
    }

    for (final m in history) {
      switch (m.role) {
        case Role.user:
          push('user', [
            {'type': 'text', 'text': m.text}
          ]);
          break;
        case Role.assistant:
          final blocks = <Map<String, dynamic>>[];
          if (m.text.isNotEmpty) {
            blocks.add({'type': 'text', 'text': m.text});
          }
          for (final c in m.toolCalls) {
            blocks.add({
              'type': 'tool_use',
              'id': c.id,
              'name': c.name,
              'input': c.args,
            });
          }
          push('assistant', blocks);
          break;
        case Role.tool:
          final r = m.toolResult!;
          // Gorsel varsa tool_result icerigi blok dizisi (metin + image) olur;
          // Claude bunu dogrudan gorur.
          final Object content;
          if (r.imageB64 != null && r.imageB64!.isNotEmpty) {
            content = [
              {'type': 'text', 'text': r.output},
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/jpeg',
                  'data': r.imageB64,
                }
              }
            ];
          } else {
            content = r.output;
          }
          push('user', [
            {
              'type': 'tool_result',
              'tool_use_id': r.callId,
              'content': content,
            }
          ]);
          break;
        case Role.system:
          break;
      }
    }
    return turns.map((t) => {'role': t['role'], 'content': t['content']}).toList();
  }

  ChatMessage _parseResponse(Map<String, dynamic> data) {
    final content = data['content'] as List?;
    if (content == null || content.isEmpty) {
      return ChatMessage(role: Role.assistant, text: '(bos yanit)');
    }
    final buffer = StringBuffer();
    final calls = <ToolCall>[];
    for (final p in content) {
      if (p is! Map) continue;
      final type = (p['type'] ?? '').toString();
      if (type == 'text') {
        buffer.write((p['text'] ?? '').toString());
      } else if (type == 'tool_use') {
        calls.add(ToolCall(
          id: (p['id'] ?? 'call_${calls.length}').toString(),
          name: (p['name'] ?? '').toString(),
          args: Map<String, dynamic>.from(p['input'] ?? const {}),
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
