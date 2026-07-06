#!/data/data/com.termux/files/usr/bin/bash
# Ajan: canli anlatim (sesli/yazili her adim) + onay isteme
set -e
cd ~/ajan_repo
mkdir -p lib/core/tools lib/core/agent lib/core/voice lib/ui lib/providers

cat > lib/core/tools/confirm_tool.dart << 'CMEOF1'
import 'package:flutter/material.dart';

import '../app_nav.dart';
import 'tool.dart';

/// Onemli/geri donusu olmayan islemlerden ONCE kullanicidan onay ister.
/// Ajan donguyu bloklar ve kullanici karar verene kadar bekler.
class ConfirmTool extends Tool {
  @override
  String get name => 'confirm';

  @override
  String get description =>
      'Onemli veya geri donusu olmayan bir islemden ONCE kullanicidan onay al. '
      'Mesaj/SMS gonderme, arama yapma, silme, satin alma, otomasyonla (screen_control) '
      'bir sey gonderme/onaylama gibi adimlardan once MUTLAKA cagir. '
      'Kullanici onaylarsa "onaylandi" doner (islemi yap), '
      'reddederse "reddedildi" doner (islemi YAPMA, iptal et).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'question': {
            'type': 'string',
            'description': 'Kullaniciya sorulacak net onay sorusu. '
                'Ornek: "Ahmet\'e \'geliyorum\' mesajini gondereyim mi?"',
          },
        },
        'required': ['question'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final question = (args['question'] ?? 'Bu islemi yapayim mi?').toString();
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return 'reddedildi (arayuz hazir degil, guvenlik icin iptal)';

    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Onay', style: TextStyle(color: Colors.white)),
        content: Text(question,
            style: const TextStyle(color: Color(0xFFD5D3E8), fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgec', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    return ok == true
        ? 'onaylandi (devam et)'
        : 'reddedildi (islemi yapma, iptal et)';
  }
}
CMEOF1

cat > lib/core/agent/tool_registry.dart << 'CMEOF2'
import '../tools/confirm_tool.dart';
import '../tools/device_tools.dart';
import '../tools/schedule_tools.dart';
import '../tools/screen_tool.dart';
import '../tools/shell_tool.dart';
import '../tools/tool.dart';
import '../tools/ui_tool.dart';

/// Tum araclarin kayit merkezi. Yeni yetenek eklemek = buraya bir satir.
class ToolRegistry {
  final Map<String, Tool> _tools = {};

  ToolRegistry() {
    _register([
      ShellTool(),
      OpenAppTool(),
      SendSmsTool(),
      LocationTool(),
      NotifyTool(),
      ScheduleNotificationTool(),
      CreateUiTool(),
      ScreenControlTool(),
      ConfirmTool(),
    ]);
  }

  void _register(List<Tool> tools) {
    for (final t in tools) {
      _tools[t.name] = t;
    }
  }

  Tool? byName(String name) => _tools[name];

  List<Map<String, dynamic>> get declarations =>
      _tools.values.map((t) => t.toDeclaration()).toList();
}
CMEOF2

cat > lib/core/voice/voice_service.dart << 'CMEOF3'
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

const _kRate = 'tts_rate';
const _kAutoSpeak = 'tts_auto';

class VoiceState {
  final bool sttReady;
  final bool listening;
  final bool speaking;
  final double rate; // 0.1 - 1.0 (konusma hizi)
  final bool autoSpeak; // gelen cevaplari otomatik seslendir

  VoiceState({
    this.sttReady = false,
    this.listening = false,
    this.speaking = false,
    this.rate = 0.5,
    this.autoSpeak = true,
  });

  VoiceState copyWith({
    bool? sttReady,
    bool? listening,
    bool? speaking,
    double? rate,
    bool? autoSpeak,
  }) =>
      VoiceState(
        sttReady: sttReady ?? this.sttReady,
        listening: listening ?? this.listening,
        speaking: speaking ?? this.speaking,
        rate: rate ?? this.rate,
        autoSpeak: autoSpeak ?? this.autoSpeak,
      );
}

/// Sesli giris (STT) ve sesli cikis (TTS) yonetimi.
class VoiceController extends StateNotifier<VoiceState> {
  VoiceController() : super(VoiceState()) {
    _init();
  }

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    final rate = p.getDouble(_kRate) ?? 0.5;
    final auto = p.getBool(_kAutoSpeak) ?? true;

    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(1.0);
    await _tts.setQueueMode(1); // QUEUE_ADD: ara adimlar ust uste binmez, sirayla okunur
    _tts.setStartHandler(() => state = state.copyWith(speaking: true));
    _tts.setCompletionHandler(() => state = state.copyWith(speaking: false));
    _tts.setCancelHandler(() => state = state.copyWith(speaking: false));

    bool ok = false;
    try {
      ok = await _stt.initialize(
        onError: (e) => debugPrint('STT error: $e'),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            state = state.copyWith(listening: false);
          }
        },
      );
    } catch (e) {
      debugPrint('STT init fail: $e');
    }

    state = state.copyWith(sttReady: ok, rate: rate, autoSpeak: auto);
  }

  /// Mikrofonu dinlemeye baslar; taninan metni [onText] ile dondurur.
  Future<void> startListening(void Function(String) onText) async {
    if (!state.sttReady) {
      await _init();
      if (!state.sttReady) return;
    }
    if (state.listening) return;
    await stopSpeaking();
    state = state.copyWith(listening: true);
    await _stt.listen(
      localeId: 'tr_TR',
      onResult: (r) {
        onText(r.recognizedWords);
        if (r.finalResult) state = state.copyWith(listening: false);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
    state = state.copyWith(listening: false);
  }

  /// Metni sesli okur. Sira modunda oldugu icin ara adimlar birbirini kesmez.
  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _tts.speak(t);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    state = state.copyWith(speaking: false);
  }

  Future<void> setRate(double rate) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kRate, rate);
    await _tts.setSpeechRate(rate);
    state = state.copyWith(rate: rate);
  }

  Future<void> setAutoSpeak(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoSpeak, v);
    state = state.copyWith(autoSpeak: v);
  }
}

final voiceProvider =
    StateNotifierProvider<VoiceController, VoiceState>((ref) => VoiceController());
CMEOF3

cat > lib/ui/chat_screen.dart << 'CMEOF4'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/native/automation.dart';
import '../core/voice/voice_service.dart';
import '../models/chat_message.dart';
import '../providers/agent_provider.dart';
import 'widgets/message_widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(voiceProvider.notifier).stopSpeaking();
    ref.read(agentProvider.notifier).sendUserMessage(text);
    _scrollDown();
  }

  void _toggleMic() {
    final voice = ref.read(voiceProvider);
    final vc = ref.read(voiceProvider.notifier);
    if (voice.listening) {
      vc.stopListening();
    } else {
      vc.startListening((text) {
        _input.text = text;
        _input.selection =
            TextSelection.collapsed(offset: _input.text.length);
      });
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  int _spokenCount = 0;

  /// Yeni gelen her asistan metnini (ara adimlar dahil) sirayla seslendirir.
  void _maybeSpeak(AgentState? prev, AgentState next) {
    if (!ref.read(voiceProvider).autoSpeak) {
      _spokenCount = next.messages.length;
      return;
    }
    // Sohbet temizlendiyse sayaci sifirla.
    if (next.messages.length < _spokenCount) _spokenCount = 0;
    final vc = ref.read(voiceProvider.notifier);
    for (var i = _spokenCount; i < next.messages.length; i++) {
      final m = next.messages[i];
      if (m.role == Role.assistant && m.text.trim().isNotEmpty) {
        vc.speak(m.text);
      }
    }
    _spokenCount = next.messages.length;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProvider);
    final voice = ref.watch(voiceProvider);
    ref.listen(agentProvider, (prev, next) {
      _scrollDown();
      _maybeSpeak(prev, next);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11111B),
        title: const Text('Ajan'),
        actions: [
          if (!state.hasKey)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.key_off, color: Colors.orangeAccent),
            ),
          if (voice.speaking)
            IconButton(
              icon: const Icon(Icons.volume_off),
              tooltip: 'Susturmayi durdur',
              onPressed: () => ref.read(voiceProvider.notifier).stopSpeaking(),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => ref.read(agentProvider.notifier).clearChat(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? const _EmptyHint()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.messages.length,
                    itemBuilder: (_, i) =>
                        MessageBubble(message: state.messages[i]),
                  ),
          ),
          if (state.busy)
            const LinearProgressIndicator(
              color: Color(0xFF6C5CE7),
              backgroundColor: Color(0xFF11111B),
            ),
          _InputBar(
            controller: _input,
            onSend: _send,
            enabled: !state.busy,
            listening: voice.listening,
            onMic: _toggleMic,
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    final notifier = ref.read(agentProvider.notifier);
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController(text: notifier.model);
    showDialog(
      context: context,
      builder: (_) => Consumer(builder: (ctx, r, __) {
        final voice = r.watch(voiceProvider);
        final vc = r.read(voiceProvider.notifier);
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Ayarlar', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: keyCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Gemini API Anahtari',
                    hintText: 'AIza...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                const SizedBox(height: 20),
                const Text('Ses', style: TextStyle(color: Color(0xFF9E9CB8))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cevaplari sesli oku',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: voice.autoSpeak,
                  activeColor: const Color(0xFF6C5CE7),
                  onChanged: (v) => vc.setAutoSpeak(v),
                ),
                Text('Konusma hizi: ${voice.rate.toStringAsFixed(2)}',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13)),
                Slider(
                  min: 0.2,
                  max: 1.0,
                  divisions: 16,
                  value: voice.rate.clamp(0.2, 1.0),
                  activeColor: const Color(0xFF6C5CE7),
                  label: voice.rate.toStringAsFixed(2),
                  onChanged: (v) => vc.setRate(v),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Dene'),
                    onPressed: () =>
                        vc.speak('Merhaba, ben senin ajaninim. Bu bir hiz denemesi.'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Ekran kontrolu',
                    style: TextStyle(color: Color(0xFF9E9CB8))),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  icon: const Icon(Icons.accessibility_new, size: 18),
                  label: const Text('Erisilebilirligi ac'),
                  onPressed: () => Automation.openAccessibilitySettings(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bubble_chart, size: 18),
                        label: const Text('Yuzen buton'),
                        onPressed: () async {
                          if (!await Automation.hasOverlayPermission()) {
                            await Automation.requestOverlayPermission();
                          } else {
                            await Automation.overlayStart();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      tooltip: 'Yuzen butonu kapat',
                      onPressed: () => Automation.overlayStop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
            FilledButton(
              onPressed: () {
                notifier.saveKey(keyCtrl.text, model: modelCtrl.text);
                Navigator.pop(ctx);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      }),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: Color(0xFF6C5CE7)),
            SizedBox(height: 16),
            Text(
              'Bir sey sor, sesle konus veya bir is ver.\n'
              'Mikrofona basip konusabilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6E6C8A), fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final bool enabled;
  final bool listening;
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onMic,
    required this.enabled,
    required this.listening,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      color: const Color(0xFF11111B),
      child: Row(
        children: [
          IconButton(
            icon: Icon(listening ? Icons.mic : Icons.mic_none,
                color: listening ? Colors.redAccent : const Color(0xFF6C5CE7)),
            onPressed: onMic,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: listening ? 'Dinliyorum...' : 'Mesaj...',
                hintStyle: const TextStyle(color: Color(0xFF6E6C8A)),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            backgroundColor: const Color(0xFF6C5CE7),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: enabled ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
CMEOF4

cat > lib/providers/agent_provider.dart << 'CMEOF5'
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
- create_ui: Kullaniciya ozel bir ekran/mini uygulama olustur (form, buton
- screen_control: Ekranda gezinip senin yerine islem yap (erisilebilirlik). Once action=read ile ekrani gor, sonra tap/type/scroll/back/home ile ilerle. Baska uygulamalarda otomasyon icin bunu kullan.
  panosu, gosterge). Kullanici bir arac/panel/form isteyince BUNU kullan.
  Ekrandaki butonlar tekrar sana komut gonderebilir.
- open_app, send_sms, get_location, notify: cihaz islemleri.

Otomasyon ve iletisim:
- Ekranda is yaparken (screen_control) HER adimdan once kisa bir cumleyle
  ne yapacagini soyle (ornek: "Arama cubuguna dokunuyorum."). Boylece
  kullanici canli takip eder.
- Onemli veya geri donusu olmayan islemlerden ONCE mutlaka confirm araciyla
  onay al: mesaj/SMS gonderme, arama, silme, satin alma, otomasyonla gonderme.
  "reddedildi" donerse islemi YAPMA.

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
CMEOF5

echo "=== Canli anlatim + onay eklendi ==="
wc -l lib/core/tools/confirm_tool.dart lib/ui/chat_screen.dart lib/providers/agent_provider.dart
echo "Simdi: git add -A && git commit -m iletisim && git push"
