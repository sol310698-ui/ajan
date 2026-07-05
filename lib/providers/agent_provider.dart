import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/agent/agent_loop.dart';
import '../core/agent/llm_client.dart';
import '../core/agent/tool_registry.dart';
import '../core/native/native_tools.dart';
import '../models/chat_message.dart';

const _kApiKey = 'gemini_api_key';
const _kModel = 'gemini_model';

const kSystemPrompt = '''
Sen kullanicinin Android telefonunda calisan kisisel bir yapay zeka AJANISIN.
Amacin: kullanicinin isini bastan sona SENIN yapman. Sadece cevap veren bir
sohbet botu degilsin; elindeki araclarla telefonda gercek islemler yaparsin.

Calisma tarzi:
- Turkce, kisa ve net konus.
- Bir isi arac ile yapabiliyorsan tahmin etme, araci CAGIR.
- Karmasik gorevleri kucuk adimlara bol ve adimlari kendin zincirle. Her arac
  sonucunu degerlendir, gerekiyorsa bir sonraki araci cagir. Gerekli tum
  adimlari tamamlamadan durma.
- Guvenli/geri alinabilir islemler icin kullanicidan tekrar tekrar onay isteme;
  isi yap ve sonucu ozetle.
- Sadece geri donusu OLMAYAN veya tehlikeli islemlerden (dosya silme, toplu
  degisiklik, mesaj gonderme) once tek cumlelik kisa bir uyari ver.

Araclar:
- run_shell: Termux uzerinde Linux komutu (python, curl, git, dosya islemleri,
  paket kurma, indirme). Ciktilari yorumla, ham ciktiya bogma.
- schedule_notification: Gecikmeli hatirlatmalar icin. "5 dakika sonra hatirlat"
  gibi istekleri BUNUNLA yap. ASLA run_shell + sleep kullanma.
- open_app, send_sms, get_location, notify: cihaz islemleri.

Uzun surecek komutlarda (buyuk indirme vb.) komutu arka plana al
(ornek: "komut > log.txt 2>&1 &") ve hemen don; sonucu sonra kontrol et.
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
  String _model = 'gemini-2.5-flash';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _apiKey = p.getString(_kApiKey) ?? '';
    _model = p.getString(_kModel) ?? 'gemini-2.5-flash';
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

    // Gorev suresince telefon uykuya girse bile baglanti kopmasin.
    await NativeTools.startAgentTask();

    final loop = AgentLoop(
      llm: LlmClient(apiKey: _apiKey, model: _model),
      registry: _registry,
      systemPrompt: kSystemPrompt,
      maxSteps: 15,
    );

    try {
      await loop.run(
        history,
        onEvent: (_) {
          state = state.copyWith(messages: List<ChatMessage>.from(history));
        },
      );
    } catch (e) {
      _append(ChatMessage(role: Role.assistant, text: 'Hata: $e'));
      if (kDebugMode) debugPrint('agent error: $e');
    } finally {
      await NativeTools.stopAgentTask();
      state = state.copyWith(busy: false);
    }
  }

  void _append(ChatMessage m) {
    state = state.copyWith(messages: [...state.messages, m]);
  }
}

final agentProvider =
    StateNotifierProvider<AgentNotifier, AgentState>((ref) => AgentNotifier());
