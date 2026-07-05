import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/agent/agent_loop.dart';
import '../core/agent/llm_client.dart';
import '../core/agent/tool_registry.dart';
import '../models/chat_message.dart';

const _kApiKey = 'gemini_api_key';
const _kModel = 'gemini_model';

const kSystemPrompt = '''
Sen kullanicinin Android telefonunda calisan kisisel bir yapay zeka ajanisin.
Turkce, kisa ve net konus. Kullanicinin sorularini cevaplarsin ve gerektiginde
elindeki araclari kullanarak telefonda islem yaparsin.

Kurallar:
- Bir isi arac ile yapabiliyorsan, tahmin etme; araci cagir.
- Karmasik isleri kucuk adimlara bol, her adimda uygun araci kullan.
- run_shell ile Termux uzerinde komut calistirabilirsin (python, curl, git,
  dosya islemleri vb.). Ciktilari yorumlayip kullaniciya ozetle.
- Geri donusu olmayan / tehlikeli komutlarda once kullaniciya kisa uyari ver.
- Arac sonucunu aldiktan sonra kullaniciya sade bir ozet sun; ham ciktiya
  bogma.
''';

class AgentState {
  final List<ChatMessage> messages;
  final bool busy;
  final bool hasKey;

  AgentState({
    this.messages = const [],
    this.busy = false,
    this.hasKey = false,
  });

  AgentState copyWith({
    List<ChatMessage>? messages,
    bool? busy,
    bool? hasKey,
  }) =>
      AgentState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
        hasKey: hasKey ?? this.hasKey,
      );
}

class AgentNotifier extends StateNotifier<AgentState> {
  AgentNotifier() : super(AgentState()) {
    _load();
  }

  final ToolRegistry _registry = ToolRegistry();
  String _apiKey = '';
  String _model = 'gemini-2.0-flash';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _apiKey = p.getString(_kApiKey) ?? '';
    _model = p.getString(_kModel) ?? 'gemini-2.0-flash';
    state = state.copyWith(hasKey: _apiKey.isNotEmpty);
  }

  Future<void> saveKey(String key, {String? model}) async {
    final p = await SharedPreferences.getInstance();
    _apiKey = key.trim();
    await p.setString(_kApiKey, _apiKey);
    if (model != null && model.isNotEmpty) {
      _model = model;
      await p.setString(_kModel, model);
    }
    state = state.copyWith(hasKey: _apiKey.isNotEmpty);
  }

  String get model => _model;

  void clearChat() => state = state.copyWith(messages: []);

  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty || state.busy) return;
    if (_apiKey.isEmpty) {
      _append(ChatMessage(
        role: Role.assistant,
        text: 'Once ayarlardan Gemini API anahtarini gir.',
      ));
      return;
    }

    final history = List<ChatMessage>.from(state.messages)
      ..add(ChatMessage(role: Role.user, text: text));
    state = state.copyWith(messages: history, busy: true);

    final loop = AgentLoop(
      llm: LlmClient(apiKey: _apiKey, model: _model),
      registry: _registry,
      systemPrompt: kSystemPrompt,
    );

    try {
      await loop.run(
        history,
        onEvent: (_) {
          // Gecmis referansi ayni; yeni liste ile state'i tazele.
          state = state.copyWith(messages: List<ChatMessage>.from(history));
        },
      );
    } catch (e) {
      _append(ChatMessage(role: Role.assistant, text: 'Hata: $e'));
      if (kDebugMode) debugPrint('agent error: $e');
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  void _append(ChatMessage m) {
    state = state.copyWith(messages: [...state.messages, m]);
  }
}

final agentProvider =
    StateNotifierProvider<AgentNotifier, AgentState>((ref) => AgentNotifier());
