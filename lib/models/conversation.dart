import 'chat_message.dart';

/// Kalici bir sohbet oturumu (baslik + mesajlar).
class Conversation {
  final String id;
  String title;
  List<ChatMessage> messages;
  DateTime updatedAt;

  Conversation({
    required this.id,
    required this.title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
  })  : messages = messages ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  /// Ilk kullanici mesajindan otomatik baslik uretir.
  void autoTitleFrom(String text) {
    if (title.isNotEmpty && title != 'Yeni sohbet') return;
    final t = text.trim().replaceAll('\n', ' ');
    if (t.isEmpty) return;
    title = t.length > 40 ? '${t.substring(0, 40)}...' : t;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? 'Sohbet').toString(),
        updatedAt:
            DateTime.tryParse((j['updatedAt'] ?? '').toString()) ?? DateTime.now(),
        messages: ((j['messages'] as List?) ?? const [])
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
