import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/conversation.dart';

/// Sohbetleri cihazda kalici saklar (SharedPreferences, JSON).
///
/// Uygulama kapanip acilinca sohbetler ve gecmis kaybolmaz; birden fazla
/// oturum tutulabilir.
class ConversationStore {
  static const _key = 'conversations_v1';
  static const _uuid = Uuid();

  Future<List<Conversation>> loadAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<Conversation> conversations) async {
    final p = await SharedPreferences.getInstance();
    final data = jsonEncode(conversations.map((c) => c.toJson()).toList());
    await p.setString(_key, data);
  }

  Conversation createNew() =>
      Conversation(id: _uuid.v4(), title: 'Yeni sohbet');
}
