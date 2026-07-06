#!/data/data/com.termux/files/usr/bin/bash
# Ajan: sesli konusma (STT giris + TTS cikis + hiz ayari)
set -e
cd ~/ajan_repo
mkdir -p lib/core/voice lib/ui android/app/src/main

cat > pubspec.yaml << 'VOEOF1'
name: ajan
description: "Dusunebilen, telefonda komut calistirabilen kisisel yapay zeka ajani."
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  http: ^1.2.2
  shared_preferences: ^2.3.2
  uuid: ^4.5.0
  intl: ^0.19.0
  speech_to_text: ^7.0.0
  flutter_tts: ^4.2.0

dev_dependencies:
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
VOEOF1

cat > lib/core/voice/voice_service.dart << 'VOEOF2'
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

  /// Metni sesli okur (autoSpeak kapaliysa yine de manuel cagrilabilir).
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
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
VOEOF2

cat > lib/ui/chat_screen.dart << 'VOEOF3'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// Gorev bitince son asistan cevabini sesli oku (autoSpeak acikken).
  void _maybeSpeak(AgentState? prev, AgentState next) {
    final finished = (prev?.busy ?? false) && !next.busy;
    if (!finished) return;
    if (!ref.read(voiceProvider).autoSpeak) return;
    final last = next.messages.lastWhere(
      (m) => m.role == Role.assistant && m.text.trim().isNotEmpty,
      orElse: () => ChatMessage(role: Role.assistant),
    );
    if (last.text.trim().isNotEmpty) {
      ref.read(voiceProvider.notifier).speak(last.text);
    }
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
VOEOF3

cat > android/app/src/main/AndroidManifest.xml << 'VOEOF4'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.SEND_SMS"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <!-- On plan servisi + wake lock (uygulama arka planda olmesin) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <!-- Zamanli bildirim -->
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <!-- Termux'a komut gonderme -->
    <uses-permission android:name="com.termux.permission.RUN_COMMAND"/>

    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN"/>
        </intent>
        <package android:name="com.termux"/>
        <!-- Sesli giris (speech_to_text) ve seslendirme (TTS) -->
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>
        <package android:name="com.google.android.googlequicksearchbox"/>
    </queries>

    <application
        android:label="Ajan"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- Kalici on plan servisi -->
        <service
            android:name=".AgentService"
            android:exported="false"
            android:foregroundServiceType="dataSync"/>

        <!-- Zamanli bildirim alicisi -->
        <receiver
            android:name=".ReminderReceiver"
            android:exported="false"/>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2"/>
    </application>
</manifest>
VOEOF4

echo "=== Sesli konusma eklendi ==="
wc -l pubspec.yaml lib/core/voice/voice_service.dart lib/ui/chat_screen.dart
echo "Simdi: git add -A && git commit -m ses && git push"
