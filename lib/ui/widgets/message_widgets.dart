import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';
import '../theme.dart';

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
        children:
            message.toolCalls.map((c) => _ToolCallCard(call: c)).toList(),
      );
    }

    final time = DateFormat('HH:mm').format(message.time);

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      decoration: BoxDecoration(
        gradient: isUser ? AppColors.brand : null,
        color: isUser ? null : AppColors.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
      ),
      child: SelectableText(
        message.text,
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
      ),
    );

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (message.hasToolCalls)
          ...message.toolCalls.map((c) => _ToolCallCard(call: c)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                Container(
                  margin: const EdgeInsets.only(left: 8, bottom: 2),
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brand,
                  ),
                  child: const Icon(Icons.smart_toy_outlined,
                      size: 17, color: Colors.white),
                ),
                const SizedBox(width: 2),
              ],
              Flexible(child: bubble),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
              left: isUser ? 0 : 50, right: isUser ? 14 : 0, bottom: 4),
          child: Text(time,
              style: const TextStyle(
                  color: AppColors.textFaint, fontSize: 10.5)),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 16, color: AppColors.primaryLight),
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
    final color = result.ok ? AppColors.success : AppColors.danger;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardDeep,
        borderRadius: BorderRadius.circular(12),
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
              color: AppColors.textSecondary,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          if (result.imageB64 != null && result.imageB64!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                base64Decode(result.imageB64!),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
