enum Role { user, assistant, tool, system }

/// Bir aracin cagrilma istegi (LLM uretir).
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  ToolCall({required this.id, required this.name, required this.args});
}

/// Bir aracin calisma sonucu.
class ToolResult {
  final String callId;
  final String name;
  final bool ok;
  final String output;

  ToolResult({
    required this.callId,
    required this.name,
    required this.ok,
    required this.output,
  });
}

/// Sohbetteki tek bir mesaj. Hem UI hem de LLM gecmisi icin kullanilir.
class ChatMessage {
  final Role role;
  final String text;

  /// assistant mesajinda model arac cagirdiysa doludur.
  final List<ToolCall> toolCalls;

  /// tool rolunde arac sonucu tasinir.
  final ToolResult? toolResult;

  final DateTime time;

  ChatMessage({
    required this.role,
    this.text = '',
    this.toolCalls = const [],
    this.toolResult,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  bool get hasToolCalls => toolCalls.isNotEmpty;
}
