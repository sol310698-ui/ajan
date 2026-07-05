import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == Role.user;

    // tool sonuclari ve arac cagrilari ayri kartlarda gosterilir.
    if (message.role == Role.tool) {
      return _ToolResultCard(result: message.toolResult!);
    }
    if (message.hasToolCalls && message.text.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: message.toolCalls
            .map((c) => _ToolCallCard(call: c))
            .toList(),
      );
    }

    final bg = isUser
        ? const Color(0xFF6C5CE7)
        : const Color(0xFF1E1E2E);
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (message.hasToolCalls)
          ...message.toolCalls.map((c) => _ToolCallCard(call: c)),
        Align(
          alignment: align,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(
              message.text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  final ToolCall call;
  const _ToolCallCard({required this.call});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF11111B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF6C5CE7), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 16, color: Color(0xFF6C5CE7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${call.name}(${_short(call.args)})',
              style: const TextStyle(
                color: Color(0xFFBAB8D4),
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _short(Map<String, dynamic> args) {
    final s = args.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }
}

class _ToolResultCard extends StatelessWidget {
  final ToolResult result;
  const _ToolResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(result.ok ? Icons.check_circle : Icons.error,
                  size: 14, color: color),
              const SizedBox(width: 6),
              Text('${result.name} sonucu',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            result.output.length > 1500
                ? '${result.output.substring(0, 1500)}\n...(kesildi)'
                : result.output,
            style: const TextStyle(
              color: Color(0xFF9E9CB8),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
