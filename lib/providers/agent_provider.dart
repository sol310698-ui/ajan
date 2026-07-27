import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/agent/agent_loop.dart';
import '../core/agent/llm_client.dart';
import '../core/agent/system_prompt.dart';
import '../core/agent/tool_registry.dart';
import '../core/native/native_tools.dart';
import '../core/settings.dart';
import '../core/store/conversation_store.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';

// Sistem talimati artik core/agent/system_prompt.dart icinde (hafiza ile
// birlikte calisma aninda uretilir). Geriye donuk import'lar icin re-export.
export '../core/agent/system_prompt.dart' show kBaseSystemPrompt;

class AgentState {
  final List<Conversation> conversations;
  final String currentId;
  final bool busy;
  final AppSettings? settings;

  AgentState({
    this.conversations = const [],
    this.currentId = '',
    this.busy = false,
    this.settings,
  });

  Conversation? get current {
    for (final c in conversations) {
      if (c.id == currentId) return c;
    }
    return conversations.isEmpty ? null : conversations.first;
  }

  List<ChatMessage> get messages => current?.messages ?? const [];
  bool get hasKey => settings?.hasKey ?? false;
  LlmProvider get provider => settings?.provider ?? LlmProvider.gemini;

  AgentState copyWith({
    List<Conversation>? conversations,
    String? currentId,
    bool? busy,
    AppSettings? settings,
  }) =>
      AgentState(
        conversations: conversations ?? this.conversations,
        currentId: currentId ?? this.currentId,
        busy: busy ?? this.busy,
        settings: settings ?? this.settings,
      );
}

class AgentNotifier extends StateNotifier<AgentState> {
  AgentNotifier() : super(AgentState()) {
    _load();
  }

  final ToolRegistry _registry = ToolRegistry();
  final ConversationStore _store = ConversationStore();

  Future<void> _load() async {
    final settings = await AppSettings.load();
    var convos = await _store.loadAll();
    if (convos.isEmpty) {
      convos = [_store.createNew()];
    }
    state = state.copyWith(
      settings: settings,
      conversations: convos,
      currentId: convos.first.id,
    );
  }

  AppSettings get settings =>
      state.settings ??
      AppSettings(
        provider: LlmProvider.gemini,
        apiKeys: <LlmProvider, String>{},
        models: <LlmProvider, String>{},
      );

  Future<void> saveSettings({
    LlmProvider? provider,
    String? apiKey,
    String? model,
  }) async {
    final s = settings;
    if (provider != null) s.provider = provider;
    if (apiKey != null) s.apiKeys[s.provider] = apiKey.trim();
    if (model != null && model.isNotEmpty) s.models[s.provider] = model.trim();
    await s.save();
    state = state.copyWith(settings: s);
  }

  // --- Sohbet yonetimi ---

  Future<void> _persist() async {
    await _store.saveAll(state.conversations);
  }

  void newConversation() {
    final c = _store.createNew();
    final list = [c, ...state.conversations];
    state = state.copyWith(conversations: list, currentId: c.id);
    _persist();
  }

  void switchConversation(String id) {
    state = state.copyWith(currentId: id);
  }

  void deleteConversation(String id) {
    var list = state.conversations.where((c) => c.id != id).toList();
    if (list.isEmpty) list = [_store.createNew()];
    final current =
        list.any((c) => c.id == state.currentId) ? state.currentId : list.first.id;
    state = state.copyWith(conversations: list, currentId: current);
    _persist();
  }

  /// Aktif sohbetin mesajlarini temizler.
  void clearChat() {
    final cur = state.current;
    if (cur == null) return;
    cur.messages = [];
    state = state.copyWith(conversations: [...state.conversations]);
    _persist();
  }

  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty || state.busy) return;
    final cur = state.current;
    if (cur == null) return;

    if (!settings.hasKey) {
      cur.messages = [
        ...cur.messages,
        ChatMessage(
          role: Role.assistant,
          text: 'Once ayarlardan (${settings.provider.label}) API anahtarini gir.',
        )
      ];
      state = state.copyWith(conversations: [...state.conversations]);
      return;
    }

    cur.messages = [...cur.messages, ChatMessage(role: Role.user, text: text)];
    cur.autoTitleFrom(text);
    cur.updatedAt = DateTime.now();
    state = state.copyWith(conversations: [...state.conversations], busy: true);

    // Gorev suresince telefon uykuya girse bile baglanti kopmasin.
    await NativeTools.startAgentTask();

    final loop = AgentLoop(
      llm: LlmClient.create(
        provider: settings.provider,
        apiKey: settings.apiKey,
        model: settings.model,
      ),
      registry: _registry,
      systemPrompt: await buildSystemPrompt(),
      maxSteps: 30,
    );

    final history = List<ChatMessage>.from(cur.messages);
    try {
      await loop.run(
        history,
        onEvent: (_) {
          cur.messages = List<ChatMessage>.from(history);
          cur.updatedAt = DateTime.now();
          state = state.copyWith(conversations: [...state.conversations]);
        },
      );
    } catch (e) {
      cur.messages = [
        ...cur.messages,
        ChatMessage(role: Role.assistant, text: 'Hata: $e')
      ];
      state = state.copyWith(conversations: [...state.conversations]);
      if (kDebugMode) debugPrint('agent error: $e');
    } finally {
      await NativeTools.stopAgentTask();
      state = state.copyWith(busy: false);
      await _persist();
    }
  }
}

final agentProvider =
    StateNotifierProvider<AgentNotifier, AgentState>((ref) => AgentNotifier());
