enum Role { user, assistant, tool, system }

/// Bir aracin cagrilma istegi (LLM uretir).
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  ToolCall({required this.id, required this.name, required this.args});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'args': args};

  factory ToolCall.fromJson(Map<String, dynamic> j) => ToolCall(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        args: Map<String, dynamic>.from(j['args'] ?? const {}),
      );
}

/// Bir aracin calisma sonucu.
class ToolResult {
  final String callId;
  final String name;
  final bool ok;
  final String output;

  /// Aracin urettigi gorsel (JPEG base64). Sadece oturum icinde modele
  /// gorsel olarak iletilir; kaliciya yazilmaz (prefs'i sismesin diye).
  final String? imageB64;

  ToolResult({
    required this.callId,
    required this.name,
    required this.ok,
    required this.output,
    this.imageB64,
  });

  // Not: imageB64 kasitli olarak JSON'a yazilmaz.
  Map<String, dynamic> toJson() =>
      {'callId': callId, 'name': name, 'ok': ok, 'output': output};

  factory ToolResult.fromJson(Map<String, dynamic> j) => ToolResult(
        callId: (j['callId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        ok: j['ok'] == true,
        output: (j['output'] ?? '').toString(),
      );
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

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'text': text,
        'toolCalls': toolCalls.map((c) => c.toJson()).toList(),
        'toolResult': toolResult?.toJson(),
        'time': time.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: Role.values.firstWhere(
          (r) => r.name == j['role'],
          orElse: () => Role.assistant,
        ),
        text: (j['text'] ?? '').toString(),
        toolCalls: ((j['toolCalls'] as List?) ?? const [])
            .map((e) => ToolCall.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        toolResult: j['toolResult'] == null
            ? null
            : ToolResult.fromJson(Map<String, dynamic>.from(j['toolResult'])),
        time: DateTime.tryParse((j['time'] ?? '').toString()) ?? DateTime.now(),
      );
}
