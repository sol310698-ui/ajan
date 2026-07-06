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
