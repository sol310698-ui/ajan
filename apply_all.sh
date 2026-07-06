#!/data/data/com.termux/files/usr/bin/bash
# Ajan: TAM SENKRON - tum kaynak dosyalari eksiksiz yazar
set -e
cd ~/ajan_repo
mkdir -p lib/models lib/core lib/core/agent lib/core/native lib/core/termux lib/core/voice lib/core/tools lib/providers lib/ui lib/ui/widgets android/app/src/main android/app/src/main/kotlin/com/sametdemiral/ajan android/app/src/main/res/xml android/app/src/main/res/values
rm -f android/app/src/main/kotlin/com/sametdemiral/ajan/AgentForegroundService.kt

cat > lib/main.dart << 'ALLEOF1'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_nav.dart';
import 'ui/chat_screen.dart';

void main() {
  runApp(const ProviderScope(child: AjanApp()));
}

class AjanApp extends StatelessWidget {
  const AjanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ajan',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
      ),
      home: const ChatScreen(),
    );
  }
}
ALLEOF1

cat > lib/models/chat_message.dart << 'ALLEOF2'
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
ALLEOF2

cat > lib/models/ui_spec.dart << 'ALLEOF3'
import 'dart:convert';

/// Ajanin urettigi dinamik ekran tarifi.
/// LLM, create_ui araciyla bu yapiyi doldurur; uygulama canli ekran cizer.
class UiSpec {
  final String title;
  final List<UiComponent> components;

  UiSpec({required this.title, required this.components});

  factory UiSpec.fromMap(Map<String, dynamic> m) {
    final comps = (m['components'] as List? ?? [])
        .whereType<Map>()
        .map((c) => UiComponent.fromMap(Map<String, dynamic>.from(c)))
        .toList();
    return UiSpec(
      title: (m['title'] ?? 'Ekran').toString(),
      components: comps,
    );
  }

  /// LLM bazen tum spec'i tek string (JSON) olarak da gonderebilir.
  static UiSpec? tryParse(dynamic raw) {
    try {
      if (raw is Map) return UiSpec.fromMap(Map<String, dynamic>.from(raw));
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return UiSpec.fromMap(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Ekrandaki tek bir bilesen.
class UiComponent {
  final String type; // text, input, stat, list, button, divider
  final String id;
  final String label;
  final String value;
  final String hint;
  final List<String> items;
  final String action; // button: prompt | submit | close
  final String payload;

  UiComponent({
    required this.type,
    this.id = '',
    this.label = '',
    this.value = '',
    this.hint = '',
    this.items = const [],
    this.action = '',
    this.payload = '',
  });

  factory UiComponent.fromMap(Map<String, dynamic> m) {
    return UiComponent(
      type: (m['type'] ?? 'text').toString(),
      id: (m['id'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      value: (m['value'] ?? '').toString(),
      hint: (m['hint'] ?? '').toString(),
      items: (m['items'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      action: (m['action'] ?? '').toString(),
      payload: (m['payload'] ?? '').toString(),
    );
  }
}
ALLEOF3

cat > lib/core/app_nav.dart << 'ALLEOF4'
import 'package:flutter/widgets.dart';

/// Global navigator: araclarin (tool) UI acabilmesi icin.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
ALLEOF4

cat > lib/core/agent/llm_client.dart << 'ALLEOF5'
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';

/// Gemini API istemcisi (function calling + otomatik yeniden deneme).
///
/// Telefon uykuya girince veya ag anlik koparsa istek dusebilir; bu durumda
/// birkac kez otomatik tekrar dener, boylece kullaniciya hata yansimaz.
class LlmClient {
  final String apiKey;
  final String model;
  final int maxRetries;

  LlmClient({
    required this.apiKey,
    this.model = 'gemini-2.5-flash',
    this.maxRetries = 3,
  });

  Uri get _endpoint => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent?key=$apiKey',
      );

  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) async {
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': _toContents(history),
      'tools': [
        {'functionDeclarations': toolDeclarations}
      ],
      'generationConfig': {'temperature': 0.4},
    });

    Object? lastErr;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final res = await http
            .post(_endpoint,
                headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 45));

        // 5xx / 429 -> gecici, tekrar denemeye deger.
        if (res.statusCode >= 500 || res.statusCode == 429) {
          lastErr = 'API ${res.statusCode}';
          await _backoff(attempt);
          continue;
        }
        if (res.statusCode != 200) {
          return ChatMessage(
            role: Role.assistant,
            text: 'API HATASI ${res.statusCode}: ${res.body}',
          );
        }
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return _parseResponse(data);
      } on SocketException catch (e) {
        // Ag kopmasi / uyku -> tekrar dene.
        lastErr = e;
        await _backoff(attempt);
      } on HttpException catch (e) {
        lastErr = e;
        await _backoff(attempt);
      } on IOException catch (e) {
        lastErr = e;
        await _backoff(attempt);
      }
    }

    return ChatMessage(
      role: Role.assistant,
      text: 'Baglanti kurulamadi ($maxRetries deneme). '
          'Internet dusuk gorunuyor, birazdan tekrar dene. [$lastErr]',
    );
  }

  Future<void> _backoff(int attempt) async {
    // 0.8s, 1.6s, 3.2s ...
    final ms = (800 * (1 << attempt)).clamp(800, 6000);
    await Future.delayed(Duration(milliseconds: ms));
  }

  List<Map<String, dynamic>> _toContents(List<ChatMessage> history) {
    final out = <Map<String, dynamic>>[];
    for (final m in history) {
      switch (m.role) {
        case Role.user:
          out.add({
            'role': 'user',
            'parts': [
              {'text': m.text}
            ]
          });
          break;
        case Role.assistant:
          final parts = <Map<String, dynamic>>[];
          if (m.text.isNotEmpty) parts.add({'text': m.text});
          for (final c in m.toolCalls) {
            parts.add({
              'functionCall': {'name': c.name, 'args': c.args}
            });
          }
          if (parts.isNotEmpty) out.add({'role': 'model', 'parts': parts});
          break;
        case Role.tool:
          final r = m.toolResult!;
          out.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': r.name,
                  'response': {'result': r.output},
                }
              }
            ]
          });
          break;
        case Role.system:
          break;
      }
    }
    return out;
  }

  ChatMessage _parseResponse(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return ChatMessage(role: Role.assistant, text: '(bos yanit)');
    }
    final parts = (candidates.first['content']?['parts'] as List?) ?? const [];
    final buffer = StringBuffer();
    final calls = <ToolCall>[];
    var callIndex = 0;

    for (final p in parts) {
      if (p is! Map) continue;
      if (p['text'] != null) buffer.write(p['text']);
      if (p['functionCall'] != null) {
        final fc = p['functionCall'] as Map;
        calls.add(ToolCall(
          id: 'call_${callIndex++}',
          name: (fc['name'] ?? '').toString(),
          args: Map<String, dynamic>.from(fc['args'] ?? {}),
        ));
      }
    }
    return ChatMessage(
      role: Role.assistant,
      text: buffer.toString().trim(),
      toolCalls: calls,
    );
  }
}
ALLEOF5

cat > lib/core/agent/agent_loop.dart << 'ALLEOF6'
import '../../models/chat_message.dart';
import 'llm_client.dart';
import 'tool_registry.dart';

/// Ajanin karar dongusu.
///
/// Akis:
///  1. Kullanici mesaji gecmise eklenir.
///  2. LLM cagrilir.
///  3. LLM arac cagirdiysa -> araclar calistirilir, sonuclar gecmise
///     eklenir, tekrar LLM cagrilir (2'ye don).
///  4. LLM duz metin dondururse -> nihai cevap, dongu biter.
///
/// [maxSteps] sonsuz donguye karsi guvenlik siniri.
class AgentLoop {
  final LlmClient llm;
  final ToolRegistry registry;
  final String systemPrompt;
  final int maxSteps;

  AgentLoop({
    required this.llm,
    required this.registry,
    required this.systemPrompt,
    this.maxSteps = 8,
  });

  /// Her adimda UI'yi guncellemek icin cagrilir (yeni mesajlar akar).
  /// onEvent, gecmise eklenen her mesajla tetiklenir.
  Future<void> run(
    List<ChatMessage> history, {
    required void Function(ChatMessage) onEvent,
  }) async {
    for (var step = 0; step < maxSteps; step++) {
      final reply = await llm.send(
        history: history,
        systemPrompt: systemPrompt,
        toolDeclarations: registry.declarations,
      );

      history.add(reply);
      onEvent(reply);

      // Arac cagrisi yoksa nihai cevap alindi -> bitir.
      if (!reply.hasToolCalls) return;

      // Cagrilan tum araclari calistir, sonuclari gecmise ekle.
      for (final call in reply.toolCalls) {
        final result = await _execute(call);
        final toolMsg = ChatMessage(role: Role.tool, toolResult: result);
        history.add(toolMsg);
        onEvent(toolMsg);
      }
    }

    // Guvenlik siniri asildi.
    final stop = ChatMessage(
      role: Role.assistant,
      text: 'Adim siniri asildi ($maxSteps). Islem durduruldu.',
    );
    history.add(stop);
    onEvent(stop);
  }

  /// Tek bir arac cagrisini calistirir ve sonucu dondurur.
  Future<ToolResult> _execute(ToolCall call) async {
    final tool = registry.byName(call.name);
    if (tool == null) {
      return ToolResult(
        callId: call.id,
        name: call.name,
        ok: false,
        output: 'Bilinmeyen arac: ${call.name}',
      );
    }
    try {
      final output = await tool.run(call.args);
      return ToolResult(
        callId: call.id,
        name: call.name,
        ok: true,
        output: output,
      );
    } catch (e) {
      return ToolResult(
        callId: call.id,
        name: call.name,
        ok: false,
        output: 'Arac hatasi: $e',
      );
    }
  }
}
ALLEOF6

cat > lib/core/agent/tool_registry.dart << 'ALLEOF7'
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
ALLEOF7

cat > lib/core/native/native_tools.dart << 'ALLEOF8'
import 'package:flutter/services.dart';

/// Native Android islemleri icin kopru (Kotlin MainActivity ile eslesir).
class NativeTools {
  static const _ch = MethodChannel('ajan/native');

  static Future<String> openApp(String query) async {
    final r = await _ch.invokeMethod<String>('openApp', {'query': query});
    return r ?? 'ok';
  }

  static Future<String> sendSms(String number, String message) async {
    final r = await _ch.invokeMethod<String>('sendSms', {
      'number': number,
      'message': message,
    });
    return r ?? 'ok';
  }

  static Future<String> getLocation() async {
    final r = await _ch.invokeMethod<String>('getLocation');
    return r ?? 'bilinmiyor';
  }

  static Future<String> notify(String title, String body) async {
    final r = await _ch.invokeMethod<String>('notify', {
      'title': title,
      'body': body,
    });
    return r ?? 'ok';
  }

  static Future<String> scheduleNotification(
      int delaySeconds, String title, String body) async {
    final r = await _ch.invokeMethod<String>('scheduleNotification', {
      'delaySeconds': delaySeconds,
      'title': title,
      'body': body,
    });
    return r ?? 'ok';
  }

  /// Gorev basladiginda cagrilir: CPU'yu uyanik tutar (wake lock).
  static Future<void> startAgentTask() async {
    try {
      await _ch.invokeMethod('startAgentTask');
    } catch (_) {}
  }

  /// Gorev bitince cagrilir: wake lock birakilir (batarya).
  static Future<void> stopAgentTask() async {
    try {
      await _ch.invokeMethod('stopAgentTask');
    } catch (_) {}
  }
}
ALLEOF8

cat > lib/core/native/automation.dart << 'ALLEOF9'
import 'package:flutter/services.dart';

/// Ekran otomasyonu ve overlay kopruleri (MainActivity ile eslesir).
class Automation {
  static const _ch = MethodChannel('ajan/native');

  static Future<String> readScreen() async =>
      await _ch.invokeMethod<String>('screenRead') ?? '(bos)';

  static Future<String> tap(String text) async =>
      await _ch.invokeMethod<String>('screenTap', {'text': text}) ?? 'ok';

  static Future<String> type(String text) async =>
      await _ch.invokeMethod<String>('screenType', {'text': text}) ?? 'ok';

  static Future<String> scroll(String direction) async =>
      await _ch.invokeMethod<String>('screenScroll', {'direction': direction}) ?? 'ok';

  static Future<String> global(String action) async =>
      await _ch.invokeMethod<String>('screenGlobal', {'action': action}) ?? 'ok';

  static Future<bool> isAccessibilityOn() async =>
      await _ch.invokeMethod<bool>('isAccessibilityOn') ?? false;

  static Future<void> openAccessibilitySettings() async =>
      await _ch.invokeMethod('openAccessibilitySettings');

  static Future<bool> hasOverlayPermission() async =>
      await _ch.invokeMethod<bool>('hasOverlayPermission') ?? false;

  static Future<void> requestOverlayPermission() async =>
      await _ch.invokeMethod('requestOverlayPermission');

  static Future<String> overlayStart() async =>
      await _ch.invokeMethod<String>('overlayStart') ?? 'ok';

  static Future<String> overlayStop() async =>
      await _ch.invokeMethod<String>('overlayStop') ?? 'ok';
}
ALLEOF9

cat > lib/core/termux/termux_bridge.dart << 'ALLEOF10'
import 'package:flutter/services.dart';

/// Termux ile kopru. Native tarafta com.termux.RUN_COMMAND intent'i ile
/// komut gonderir, cikti bir dosyaya yazilir ve geri okunur.
///
/// Gereksinimler (kullanici bir kez yapar):
///  1. Termux ve Termux:API kurulu (F-Droid).
///  2. ~/.termux/termux.properties icinde: allow-external-apps=true
///  3. `termux-setup-storage` calistirilmis olmali.
class TermuxBridge {
  static const _ch = MethodChannel('ajan/native');

  /// Bir shell komutu calistirir ve stdout+stderr dondurur.
  /// [timeoutSec] sure asiminda islem iptal edilir.
  static Future<String> run(String command, {int timeoutSec = 60}) async {
    try {
      final result = await _ch.invokeMethod<String>('termuxRun', {
        'command': command,
        'timeoutSec': timeoutSec,
      });
      return result ?? '(bos cikti)';
    } on PlatformException catch (e) {
      return 'HATA (termux): ${e.message}';
    }
  }
}
ALLEOF10

cat > lib/core/voice/voice_service.dart << 'ALLEOF11'
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
ALLEOF11

cat > lib/core/tools/tool.dart << 'ALLEOF12'
/// Ajanin kullanabilecegi tek bir yetenek (arac).
///
/// Yeni bir yetenek eklemek icin bu sinifi genislet ve ToolRegistry'e ekle.
abstract class Tool {
  /// LLM'in cagirirken kullanacagi benzersiz isim (snake_case).
  String get name;

  /// Modelin ne zaman kullanacagini anlamasi icin net aciklama.
  String get description;

  /// Parametre semasi (JSON Schema - Gemini "parameters" formati).
  Map<String, dynamic> get parameters;

  /// Araci calistirir. args model tarafindan uretilen parametrelerdir.
  /// Donen metin modele geri beslenir, o yuzden ozetleyici ve net olmali.
  Future<String> run(Map<String, dynamic> args);

  /// Gemini functionDeclarations formatina cevirir.
  Map<String, dynamic> toDeclaration() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}
ALLEOF12

cat > lib/core/tools/shell_tool.dart << 'ALLEOF13'
import '../termux/termux_bridge.dart';
import 'tool.dart';

/// Telefonda (Termux uzerinden) shell komutu calistirir.
/// Ajanin en guclu araci: python, curl, git, dosya islemleri vs.
class ShellTool extends Tool {
  @override
  String get name => 'run_shell';

  @override
  String get description =>
      'Telefonda Termux uzerinden bir Linux shell komutu calistirir. '
      'Dosya islemleri, python, curl, git, sistem bilgisi vb. icin kullan. '
      'Cikti (stdout+stderr) geri dondurulur. Tehlikeli/geri donusu olmayan '
      'komutlarda dikkatli ol.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Calistirilacak tam shell komutu.',
          },
        },
        'required': ['command'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final cmd = (args['command'] ?? '').toString().trim();
    if (cmd.isEmpty) return 'HATA: bos komut.';
    return TermuxBridge.run(cmd);
  }
}
ALLEOF13

cat > lib/core/tools/device_tools.dart << 'ALLEOF14'
import '../native/native_tools.dart';
import 'tool.dart';

class OpenAppTool extends Tool {
  @override
  String get name => 'open_app';
  @override
  String get description =>
      'Bir uygulamayi acar. Uygulama adi (ornek: "WhatsApp", "Ayarlar") '
      'veya paket adi verilebilir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Uygulama adi veya paket adi.',
          },
        },
        'required': ['query'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      NativeTools.openApp((args['query'] ?? '').toString());
}

class SendSmsTool extends Tool {
  @override
  String get name => 'send_sms';
  @override
  String get description => 'Verilen numaraya SMS gonderir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'number': {'type': 'string', 'description': 'Telefon numarasi.'},
          'message': {'type': 'string', 'description': 'Mesaj metni.'},
        },
        'required': ['number', 'message'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.sendSms(
        (args['number'] ?? '').toString(),
        (args['message'] ?? '').toString(),
      );
}

class LocationTool extends Tool {
  @override
  String get name => 'get_location';
  @override
  String get description => 'Cihazin anlik konumunu (enlem,boylam) dondurur.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.getLocation();
}

class NotifyTool extends Tool {
  @override
  String get name => 'notify';
  @override
  String get description => 'Cihazda bir bildirim gosterir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Bildirim basligi.'},
          'body': {'type': 'string', 'description': 'Bildirim metni.'},
        },
        'required': ['title', 'body'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.notify(
        (args['title'] ?? '').toString(),
        (args['body'] ?? '').toString(),
      );
}
ALLEOF14

cat > lib/core/tools/schedule_tools.dart << 'ALLEOF15'
import '../native/native_tools.dart';
import 'tool.dart';

/// Gecikmeli/zamanli bildirim planlar. "5 dakika sonra hatirlat" gibi
/// istekler icin BUNU kullan; run_shell + sleep KULLANMA (o bloklar/timeout olur).
class ScheduleNotificationTool extends Tool {
  @override
  String get name => 'schedule_notification';

  @override
  String get description =>
      'Belirtilen sure (saniye) sonra bir bildirim/hatirlatma planlar. '
      'Ornek: "5 dakika sonra hatirlat" -> delay_seconds=300. '
      'Telefon kapali/uykuda olsa bile tam zamaninda calisir. '
      'Gecikmeli hatirlatmalar icin HER ZAMAN bunu kullan, sleep KULLANMA.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'delay_seconds': {
            'type': 'integer',
            'description': 'Kac saniye sonra bildirim gelsin (5 dk = 300).',
          },
          'title': {'type': 'string', 'description': 'Bildirim basligi.'},
          'body': {'type': 'string', 'description': 'Bildirim metni.'},
        },
        'required': ['delay_seconds', 'title', 'body'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) {
    final delay = (args['delay_seconds'] is int)
        ? args['delay_seconds'] as int
        : int.tryParse('${args['delay_seconds']}') ?? 60;
    return NativeTools.scheduleNotification(
      delay,
      (args['title'] ?? 'Hatirlatma').toString(),
      (args['body'] ?? '').toString(),
    );
  }
}
ALLEOF15

cat > lib/core/tools/ui_tool.dart << 'ALLEOF16'
import 'package:flutter/material.dart';

import '../../models/ui_spec.dart';
import '../../ui/dynamic_screen.dart';
import '../app_nav.dart';
import 'tool.dart';

/// Ajanin duruma gore dinamik ekran (mini uygulama) uretmesini saglar.
/// LLM ekrani JSON olarak tarif eder; uygulama aninda canli cizer.
class CreateUiTool extends Tool {
  @override
  String get name => 'create_ui';

  @override
  String get description =>
      'Kullaniciya OZEL bir ekran/arayuz olusturur ve aninda acar. '
      'Form, buton panosu, gosterge (dashboard), liste vb. icin kullan. '
      'Bilesenler: text (bilgi), input (veri girisi), stat (etiket+deger), '
      'list (madde listesi), button (aksiyon), divider (ayrac). '
      'Button action turleri: "prompt" (label/payload metnini ajana gonderir), '
      '"submit" (formdaki tum input degerlerini toplayip ajana gonderir), '
      '"close" (ekrani kapatir). Ekrani actiktan sonra kullaniciya kisa bilgi ver.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Ekran basligi.'},
          'components': {
            'type': 'array',
            'description': 'Ekran bilesenleri (sirayla).',
            'items': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'description': 'text | input | stat | list | button | divider',
                },
                'id': {'type': 'string', 'description': 'input icin anahtar.'},
                'label': {'type': 'string'},
                'value': {'type': 'string'},
                'hint': {'type': 'string'},
                'items': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'action': {
                  'type': 'string',
                  'description': 'button icin: prompt | submit | close',
                },
                'payload': {
                  'type': 'string',
                  'description': 'button basilinca ajana gidecek metin.',
                },
              },
              'required': ['type'],
            },
          },
        },
        'required': ['title', 'components'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final spec = UiSpec.fromMap(args);
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      return 'HATA: ekran acilamadi (navigator hazir degil).';
    }
    nav.push(MaterialPageRoute(builder: (_) => DynamicScreen(spec: spec)));
    final n = spec.components.length;
    return 'Ekran acildi: "${spec.title}" ($n bilesen).';
  }
}
ALLEOF16

cat > lib/core/tools/screen_tool.dart << 'ALLEOF17'
import '../native/automation.dart';
import 'tool.dart';

/// Ekranda gezinme + otomasyon: ekrani okur, dokunur, yazar, kaydirir,
/// geri/ana ekran gibi genel islemleri yapar. (Erisilebilirlik gerekir.)
class ScreenControlTool extends Tool {
  @override
  String get name => 'screen_control';

  @override
  String get description =>
      'Telefon ekraninda senin yerine islem yapar (erisilebilirlik). '
      'action degerleri: '
      '"read" (ekrandaki metinleri oku - once bunu kullanip ekrani gor), '
      '"tap" (text ile eslesen ogeye dokun), '
      '"type" (yazilabilir alana text yaz), '
      '"scroll" (direction: up/down), '
      '"back"/"home"/"recents"/"notifications" (genel islemler). '
      'Bir uygulamada is yaparken once "read" ile ekrani gor, sonra "tap"/"type" ile ilerle.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': 'read | tap | type | scroll | back | home | recents | notifications',
          },
          'text': {
            'type': 'string',
            'description': 'tap icin dokunulacak metin; type icin yazilacak metin.',
          },
          'direction': {
            'type': 'string',
            'description': 'scroll icin: up veya down.',
          },
        },
        'required': ['action'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final action = (args['action'] ?? '').toString();
    final text = (args['text'] ?? '').toString();
    final dir = (args['direction'] ?? 'down').toString();

    if (!await Automation.isAccessibilityOn()) {
      await Automation.openAccessibilitySettings();
      return 'Erisilebilirlik kapali. Acilan ayar ekranindan "Ajan"i etkinlestir, '
          'sonra tekrar dene.';
    }

    switch (action) {
      case 'read':
        return 'EKRAN:\n${await Automation.readScreen()}';
      case 'tap':
        return await Automation.tap(text);
      case 'type':
        return await Automation.type(text);
      case 'scroll':
        return await Automation.scroll(dir);
      case 'back':
      case 'home':
      case 'recents':
      case 'notifications':
        return await Automation.global(action);
      default:
        return 'Bilinmeyen islem: $action';
    }
  }
}
ALLEOF17

cat > lib/core/tools/confirm_tool.dart << 'ALLEOF18'
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
ALLEOF18

cat > lib/providers/agent_provider.dart << 'ALLEOF19'
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
ALLEOF19

cat > lib/ui/chat_screen.dart << 'ALLEOF20'
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
ALLEOF20

cat > lib/ui/dynamic_screen.dart << 'ALLEOF21'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_spec.dart';
import '../providers/agent_provider.dart';

/// Ajanin urettigi UiSpec'i canli bir ekran olarak cizer.
/// Butonlar tekrar ajana mesaj gonderebilir (prompt/submit) veya ekrani kapatir.
class DynamicScreen extends ConsumerStatefulWidget {
  final UiSpec spec;
  const DynamicScreen({super.key, required this.spec});

  @override
  ConsumerState<DynamicScreen> createState() => _DynamicScreenState();
}

class _DynamicScreenState extends ConsumerState<DynamicScreen> {
  final Map<String, TextEditingController> _inputs = {};

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String id) =>
      _inputs.putIfAbsent(id, () => TextEditingController());

  void _handleAction(UiComponent b) {
    switch (b.action) {
      case 'close':
        Navigator.of(context).maybePop();
        break;
      case 'submit':
        final data = _inputs.entries
            .map((e) => '${e.key}=${e.value.text}')
            .join(', ');
        final msg = b.payload.isNotEmpty
            ? '${b.payload} [$data]'
            : 'Form gonderildi: [$data]';
        Navigator.of(context).maybePop();
        ref.read(agentProvider.notifier).sendUserMessage(msg);
        break;
      case 'prompt':
      default:
        final msg = b.payload.isNotEmpty ? b.payload : b.label;
        Navigator.of(context).maybePop();
        ref.read(agentProvider.notifier).sendUserMessage(msg);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11111B),
        title: Text(widget.spec.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: widget.spec.components.map(_build).toList(),
      ),
    );
  }

  Widget _build(UiComponent c) {
    switch (c.type) {
      case 'text':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(c.value.isNotEmpty ? c.value : c.label,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
        );
      case 'input':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _ctrl(c.id.isNotEmpty ? c.id : c.label),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: c.label,
              hintText: c.hint,
              filled: true,
              fillColor: const Color(0xFF1E1E2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        );
      case 'stat':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(c.label,
                  style: const TextStyle(color: Color(0xFF9E9CB8), fontSize: 14)),
              Text(c.value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        );
      case 'list':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: c.items
              .map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Text('•  ',
                          style: TextStyle(color: Color(0xFF6C5CE7))),
                      Expanded(
                          child: Text(it,
                              style: const TextStyle(color: Colors.white))),
                    ]),
                  ))
              .toList(),
        );
      case 'button':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _handleAction(c),
              child: Text(c.label),
            ),
          ),
        );
      case 'divider':
        return const Divider(color: Color(0xFF2A2A3A), height: 24);
      default:
        return const SizedBox.shrink();
    }
  }
}
ALLEOF21

cat > lib/ui/widgets/message_widgets.dart << 'ALLEOF22'
import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == Role.user;

    // tool sonuclari ve arac cagrilari ayri kartlarda gosterilir.
    if (message.role == Role.tool) {
      return _ToolResultCard(result: message.toolResult!);
    }
    if (message.hasToolCalls && message.text.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: message.toolCalls
            .map((c) => _ToolCallCard(call: c))
            .toList(),
      );
    }

    final bg = isUser
        ? const Color(0xFF6C5CE7)
        : const Color(0xFF1E1E2E);
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (message.hasToolCalls)
          ...message.toolCalls.map((c) => _ToolCallCard(call: c)),
        Align(
          alignment: align,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(
              message.text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  final ToolCall call;
  const _ToolCallCard({required this.call});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF11111B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF6C5CE7), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 16, color: Color(0xFF6C5CE7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${call.name}(${_short(call.args)})',
              style: const TextStyle(
                color: Color(0xFFBAB8D4),
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _short(Map<String, dynamic> args) {
    final s = args.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }
}

class _ToolResultCard extends StatelessWidget {
  final ToolResult result;
  const _ToolResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(result.ok ? Icons.check_circle : Icons.error,
                  size: 14, color: color),
              const SizedBox(width: 6),
              Text('${result.name} sonucu',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            result.output.length > 1500
                ? '${result.output.substring(0, 1500)}\n...(kesildi)'
                : result.output,
            style: const TextStyle(
              color: Color(0xFF9E9CB8),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
ALLEOF22

cat > pubspec.yaml << 'ALLEOF23'
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
ALLEOF23

cat > android/app/src/main/AndroidManifest.xml << 'ALLEOF24'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
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

        <!-- Ekranda gezinme / otomasyon (erisilebilirlik) -->
        <service
            android:name=".AjanAccessibilityService"
            android:exported="false"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService"/>
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_config"/>
        </service>

        <!-- Yuzen buton -->
        <service
            android:name=".OverlayService"
            android:exported="false"/>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2"/>
    </application>
</manifest>
ALLEOF24

cat > android/app/src/main/res/xml/accessibility_config.xml << 'ALLEOF25'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeAllMask"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagDefault|flagRetrieveInteractiveWindows"
    android:canPerformGestures="true"
    android:canRetrieveWindowContent="true"
    android:description="@string/accessibility_desc"
    android:notificationTimeout="100"/>
ALLEOF25

cat > android/app/src/main/res/values/strings.xml << 'ALLEOF26'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="accessibility_desc">Ajan ekranda gezinip senin yerine dokunma, yazma ve kaydirma islemleri yapar.</string>
</resources>
ALLEOF26

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/MainActivity.kt << 'ALLEOF27'
package com.sametdemiral.ajan

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.telephony.SmsManager
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private val channel = "ajan/native"
    private val main = Handler(Looper.getMainLooper())

    private val pending = HashMap<Int, MethodChannel.Result>()
    private val timeouts = HashMap<Int, Runnable>()
    private val idGen = AtomicInteger(1000)

    private val resultAction = "com.sametdemiral.ajan.TERMUX_RESULT"
    private val runCommandPermission = "com.termux.permission.RUN_COMMAND"
    private val reqRunCommand = 2001
    private var receiver: BroadcastReceiver? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNeededPermissions()
        startAgentService()
    }

    private fun startAgentService() {
        val i = Intent(this, AgentService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(i)
        } else {
            startService(i)
        }
    }

    // Gorev suresince CPU'yu uyanik tutar; en fazla 15 dk guvenlik siniri.
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ajan:task").apply {
            setReferenceCounted(false)
            acquire(15 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
    }

    private fun requestNeededPermissions() {
        val want = mutableListOf<String>()
        if (checkSelfPermission(runCommandPermission) != PackageManager.PERMISSION_GRANTED)
            want.add(runCommandPermission)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                != PackageManager.PERMISSION_GRANTED)
            want.add("android.permission.POST_NOTIFICATIONS")
        if (want.isNotEmpty()) requestPermissions(want.toTypedArray(), reqRunCommand)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerTermuxReceiver()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "termuxRun" -> runTermux(
                        call.argument<String>("command") ?: "",
                        call.argument<Int>("timeoutSec") ?: 60,
                        result
                    )
                    "openApp" -> openApp(call.argument<String>("query") ?: "", result)
                    "sendSms" -> sendSms(
                        call.argument<String>("number") ?: "",
                        call.argument<String>("message") ?: "",
                        result
                    )
                    "getLocation" -> result.success("konum servisi henuz baglanmadi")
                    "notify" -> notify(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("body") ?: "",
                        result
                    )
                    "scheduleNotification" -> scheduleNotification(
                        call.argument<Int>("delaySeconds") ?: 60,
                        call.argument<String>("title") ?: "Hatirlatma",
                        call.argument<String>("body") ?: "",
                        result
                    )
                    "startAgentTask" -> { acquireWakeLock(); result.success("ok") }
                    "stopAgentTask" -> { releaseWakeLock(); result.success("ok") }
                    "screenRead" -> result.success(
                        AjanAccessibilityService.instance?.readScreen()
                            ?: "Erisim servisi kapali. Ayarlar > Erisilebilirlik > Ajan'i ac.")
                    "screenTap" -> {
                        val ok = AjanAccessibilityService.instance
                            ?.tapText(call.argument<String>("text") ?: "") ?: false
                        result.success(if (ok) "tiklandi" else "bulunamadi/erisim kapali")
                    }
                    "screenType" -> {
                        val ok = AjanAccessibilityService.instance
                            ?.setText(call.argument<String>("text") ?: "") ?: false
                        result.success(if (ok) "yazildi" else "yazilabilir alan yok/erisim kapali")
                    }
                    "screenScroll" -> {
                        val fwd = (call.argument<String>("direction") ?: "down") != "up"
                        val ok = AjanAccessibilityService.instance?.scroll(fwd) ?: false
                        result.success(if (ok) "kaydirildi" else "kaydirilabilir alan yok")
                    }
                    "screenGlobal" -> {
                        val ok = AjanAccessibilityService.instance
                            ?.doGlobal(call.argument<String>("action") ?: "") ?: false
                        result.success(if (ok) "yapildi" else "erisim kapali")
                    }
                    "isAccessibilityOn" ->
                        result.success(AjanAccessibilityService.instance != null)
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(android.provider.Settings
                            .ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success("ok")
                    }
                    "hasOverlayPermission" ->
                        result.success(android.provider.Settings.canDrawOverlays(this))
                    "requestOverlayPermission" -> {
                        startActivity(Intent(android.provider.Settings
                            .ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success("ok")
                    }
                    "overlayStart" -> {
                        if (android.provider.Settings.canDrawOverlays(this)) {
                            startService(Intent(this, OverlayService::class.java))
                            result.success("ok")
                        } else result.success("izin yok")
                    }
                    "overlayStop" -> {
                        stopService(Intent(this, OverlayService::class.java))
                        result.success("ok")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerTermuxReceiver() {
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val id = intent?.getIntExtra("exec_id", -1) ?: -1
                val bundle: Bundle? = intent?.getBundleExtra("result")
                val stdout = bundle?.getString("stdout") ?: ""
                val stderr = bundle?.getString("stderr") ?: ""
                val err = bundle?.getInt("err", 0) ?: 0
                val errmsg = bundle?.getString("errmsg") ?: ""
                val exitCode = bundle?.getInt("exitCode", -1) ?: -1

                val text = buildString {
                    if (stdout.isNotBlank()) append(stdout.trimEnd())
                    if (stderr.isNotBlank()) {
                        if (isNotEmpty()) append("\n")
                        append(stderr.trimEnd())
                    }
                    // err=-1 sadece cikis kodu bildirimidir; cikti varsa gurultu,
                    // gosterme. Sadece cikti hic yoksa ve gercek hata varsa yaz.
                    if (err != 0 && err != -1 && isEmpty()) {
                        append("[plugin hatasi err=" + err + " " + errmsg + "]")
                    }
                    if (isEmpty()) append("(komut bitti, cikti yok. exit=" + exitCode + ")")
                }
                complete(id, text)
            }
        }
        val filter = IntentFilter(resultAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun runTermux(command: String, timeoutSec: Int, result: MethodChannel.Result) {
        if (command.isBlank()) { result.success("HATA: bos komut."); return }

        if (checkSelfPermission(runCommandPermission) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(runCommandPermission), reqRunCommand)
            result.success("Termux izni henuz verilmemis. Ekranda cikan izin " +
                "penceresinde IZIN VER de, sonra komutu tekrar dene.")
            return
        }

        val id = idGen.incrementAndGet()
        pending[id] = result

        val callback = Intent(resultAction).apply {
            setPackage(packageName)
            putExtra("exec_id", id)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        else
            PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getBroadcast(this, id, callback, flags)

        val intent = Intent().apply {
            setClassName("com.termux", "com.termux.app.RunCommandService")
            action = "com.termux.RUN_COMMAND"
            putExtra("com.termux.RUN_COMMAND_PATH",
                "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", command))
            putExtra("com.termux.RUN_COMMAND_WORKDIR",
                "/data/data/com.termux/files/home")
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0")
            putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pi)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            complete(id, "HATA: Termux baslatilamadi (" + e.message + ").")
            return
        }

        val to = Runnable {
            complete(id, "HATA: Termux sonucu " + timeoutSec + " sn icinde donmedi. " +
                "Termux acik mi ve allow-external-apps=true mi?")
        }
        timeouts[id] = to
        main.postDelayed(to, timeoutSec * 1000L)
    }

    private fun complete(id: Int, text: String) {
        main.post {
            timeouts.remove(id)?.let { main.removeCallbacks(it) }
            pending.remove(id)?.success(text)
        }
    }

    private fun scheduleNotification(
        delaySec: Int, title: String, body: String, result: MethodChannel.Result) {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val nid = (System.currentTimeMillis() % 100000).toInt()
        val i = Intent(this, ReminderReceiver::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
            putExtra("nid", nid)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getBroadcast(this, nid, i, flags)
        val at = System.currentTimeMillis() + delaySec * 1000L
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
                result.success("Bildirim ~" + delaySec + " sn sonraya planlandi (yaklasik).")
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                result.success("Bildirim " + delaySec + " sn sonraya planlandi.")
            }
        } catch (e: SecurityException) {
            am.set(AlarmManager.RTC_WAKEUP, at, pi)
            result.success("Bildirim planlandi (yaklasik).")
        }
    }

    private fun openApp(query: String, result: MethodChannel.Result) {
        val pm = packageManager
        var launch = pm.getLaunchIntentForPackage(query)
        if (launch == null) {
            val apps = pm.getInstalledApplications(0)
            val match = apps.firstOrNull {
                val label = pm.getApplicationLabel(it).toString()
                label.equals(query, true) || label.contains(query, true)
            }
            if (match != null) launch = pm.getLaunchIntentForPackage(match.packageName)
        }
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launch)
            result.success("acildi: " + query)
        } else {
            result.success("bulunamadi: " + query)
        }
    }

    private fun sendSms(number: String, message: String, result: MethodChannel.Result) {
        try {
            @Suppress("DEPRECATION")
            val sms = SmsManager.getDefault()
            sms.sendTextMessage(number, null, message, null, null)
            result.success("SMS gonderildi: " + number)
        } catch (e: Exception) {
            result.success("SMS hatasi: " + e.message)
        }
    }

    private fun notify(title: String, body: String, result: MethodChannel.Result) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val chId = "ajan_default"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(chId, "Ajan", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val n = NotificationCompat.Builder(this, chId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()
        nm.notify(System.currentTimeMillis().toInt(), n)
        result.success("bildirim gosterildi")
    }

    override fun onDestroy() {
        receiver?.let { runCatching { unregisterReceiver(it) } }
        releaseWakeLock()
        super.onDestroy()
    }
}
ALLEOF27

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/AgentService.kt << 'ALLEOF28'
package com.sametdemiral.ajan

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Kalici on plan servisi. Amac: uygulama arka planda / ekran kapaliyken
 * oldurulmesin ve ag istekleri Doze kisitlamasindan etkilenmesin.
 *
 * Wake lock BURADA tutulmaz (batarya icin). CPU'yu uyanik tutma isi
 * MainActivity'de gorev basina yapilir (startAgentTask/stopAgentTask).
 *
 * START_STICKY: sistem oldururse yeniden baslatir.
 */
class AgentService : Service() {
    private val chId = "ajan_service"
    private val notifId = 42

    override fun onCreate() {
        super.onCreate()
        startForeground(notifId, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(chId, "Ajan Servisi",
                NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, open,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE else 0
        )
        return NotificationCompat.Builder(this, chId)
            .setContentTitle("Ajan aktif")
            .setContentText("Arka planda calismaya hazir.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
ALLEOF28

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/ReminderReceiver.kt << 'ALLEOF29'
package com.sametdemiral.ajan

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * AlarmManager tetiklendiginde bildirimi gosterir.
 * Uygulama kapali olsa bile calisir (manifest'te kayitli).
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Hatirlatma"
        val body = intent.getStringExtra("body") ?: ""
        val nid = intent.getIntExtra("nid", 1)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val chId = "ajan_reminder"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(chId, "Ajan Hatirlatma",
                    NotificationManager.IMPORTANCE_HIGH))
        }
        val n = NotificationCompat.Builder(context, chId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        nm.notify(nid, n)
    }
}
ALLEOF29

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/AjanAccessibilityService.kt << 'ALLEOF30'
package com.sametdemiral.ajan

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Ekranda gezinme + otomasyon: ekrani okur, metne dokunur, yazi yazar,
 * kaydirir, geri/ana ekran gibi genel islemleri yapar.
 *
 * MainActivity, statik [instance] uzerinden bu servisi cagirir.
 * Kullanici bunu bir kez Ayarlar > Erisilebilirlik > Ajan'dan acmali.
 */
class AjanAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: AjanAccessibilityService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    /** Ekrandaki gorunur metinleri toplayip dondurur (ajanin "gozu"). */
    fun readScreen(): String {
        val root = rootInActiveWindow ?: return "(ekran okunamadi)"
        val sb = StringBuilder()
        collectText(root, sb, 0)
        val out = sb.toString().trim()
        return if (out.isEmpty()) "(gorunur metin yok)" else out.take(4000)
    }

    private fun collectText(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 40) return
        val t = node.text?.toString()?.trim()
        val d = node.contentDescription?.toString()?.trim()
        val label = when {
            !t.isNullOrEmpty() -> t
            !d.isNullOrEmpty() -> d
            else -> null
        }
        if (label != null) {
            val tag = if (node.isClickable) "[tikla] " else ""
            sb.append(tag).append(label).append("\n")
        }
        for (i in 0 until node.childCount) {
            collectText(node.getChild(i), sb, depth + 1)
        }
    }

    /** Metni iceren ilk tiklanabilir ogeyi bulup tiklar. */
    fun tapText(target: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findByText(root, target) ?: return false
        var n: AccessibilityNodeInfo? = node
        while (n != null) {
            if (n.isClickable) {
                return n.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            n = n.parent
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun findByText(root: AccessibilityNodeInfo, target: String): AccessibilityNodeInfo? {
        val lower = target.lowercase()
        // Once dogrudan metin eslesmesi
        val hits = root.findAccessibilityNodeInfosByText(target)
        if (!hits.isNullOrEmpty()) return hits[0]
        // Sonra icerik aciklamasi / kismi eslesme
        return searchNode(root, lower)
    }

    private fun searchNode(node: AccessibilityNodeInfo?, lower: String): AccessibilityNodeInfo? {
        if (node == null) return null
        val t = node.text?.toString()?.lowercase()
        val d = node.contentDescription?.toString()?.lowercase()
        if ((t != null && t.contains(lower)) || (d != null && d.contains(lower))) return node
        for (i in 0 until node.childCount) {
            val r = searchNode(node.getChild(i), lower)
            if (r != null) return r
        }
        return null
    }

    /** Odaktaki (veya ilk) yazilabilir alana metin yazar. */
    fun setText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val field = findEditable(root) ?: return false
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun findEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable && node.isFocused) return node
        for (i in 0 until node.childCount) {
            val r = findEditable(node.getChild(i))
            if (r != null) return r
        }
        // odakli yoksa ilk yazilabiliri dene
        if (node.isEditable) return node
        return null
    }

    fun scroll(forward: Boolean): Boolean {
        val root = rootInActiveWindow ?: return false
        val s = findScrollable(root) ?: return false
        val action = if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        return s.performAction(action)
    }

    private fun findScrollable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val r = findScrollable(node.getChild(i))
            if (r != null) return r
        }
        return null
    }

    fun doGlobal(action: String): Boolean {
        val a = when (action) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            else -> return false
        }
        return performGlobalAction(a)
    }
}
ALLEOF30

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/OverlayService.kt << 'ALLEOF31'
package com.sametdemiral.ajan

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * Ekranin uzerinde duran yuzen buton (baloncuk). Her uygulamanin ustunde
 * gorunur; dokununca Ajan'i one getirir, surukleyerek tasinabilir.
 * "Diger uygulamalarin uzerinde goster" izni gerekir.
 */
class OverlayService : Service() {
    private var wm: WindowManager? = null
    private var bubble: View? = null

    override fun onCreate() {
        super.onCreate()
        showBubble()
    }

    private fun showBubble() {
        if (bubble != null) return
        wm = getSystemService(WINDOW_SERVICE) as WindowManager

        val size = (56 * resources.displayMetrics.density).toInt()
        val view = FrameLayout(this).apply {
            val tv = TextView(context).apply {
                text = "A"
                setTextColor(Color.WHITE)
                textSize = 22f
                gravity = Gravity.CENTER
            }
            addView(tv)
            setBackgroundColor(Color.parseColor("#6C5CE7"))
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            size, size, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = 300
        }

        // Suruklenebilir + tikla
        var startX = 0; var startY = 0
        var touchX = 0f; var touchY = 0f
        var moved = false
        view.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x; startY = params.y
                    touchX = e.rawX; touchY = e.rawY; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - touchX).toInt()
                    val dy = (e.rawY - touchY).toInt()
                    if (abs(dx) > 10 || abs(dy) > 10) moved = true
                    params.x = startX + dx
                    params.y = startY + dy
                    wm?.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) openApp()
                    true
                }
                else -> false
            }
        }

        bubble = view
        runCatching { wm?.addView(view, params) }
    }

    private fun openApp() {
        val i = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        if (i != null) startActivity(i)
    }

    override fun onDestroy() {
        bubble?.let { runCatching { wm?.removeView(it) } }
        bubble = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
ALLEOF31

echo "=== TAM SENKRON TAMAM (31 dosya) ==="
echo "Dart dosya sayisi:"; find lib -name "*.dart" | wc -l
echo "Simdi: git add -A && git commit -m senkron && git push"
