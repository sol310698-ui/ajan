#!/data/data/com.termux/files/usr/bin/bash
# Ajan v2: retry + zamanli bildirim + on plan servisi
# Kullanim: ~/ajan_repo icinde calistir
set -e
cd ~/ajan_repo
mkdir -p lib/core/agent lib/core/tools lib/core/native lib/providers android/app/src/main/kotlin/com/sametdemiral/ajan android/app/src/main

cat > lib/core/agent/llm_client.dart << 'AJEOF01'
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
AJEOF01

cat > lib/core/agent/tool_registry.dart << 'AJEOF02'
import '../tools/device_tools.dart';
import '../tools/schedule_tools.dart';
import '../tools/shell_tool.dart';
import '../tools/tool.dart';

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
AJEOF02

cat > lib/core/native/native_tools.dart << 'AJEOF03'
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

  /// [delaySeconds] saniye sonra bir bildirim planlar (AlarmManager).
  static Future<String> scheduleNotification(
      int delaySeconds, String title, String body) async {
    final r = await _ch.invokeMethod<String>('scheduleNotification', {
      'delaySeconds': delaySeconds,
      'title': title,
      'body': body,
    });
    return r ?? 'ok';
  }
}
AJEOF03

cat > lib/core/tools/schedule_tools.dart << 'AJEOF04'
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
AJEOF04

cat > lib/providers/agent_provider.dart << 'AJEOF05'
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
AJEOF05

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/MainActivity.kt << 'AJEOF06'
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
        super.onDestroy()
    }
}
AJEOF06

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/AgentService.kt << 'AJEOF07'
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
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Kalici on plan servisi. Amac: uygulama arka planda / ekran kapaliyken
 * oldurulmesin ve ag istekleri kesilmesin.
 *
 * - Kalici bir bildirim gosterir (Android sarti).
 * - Kismi wake lock tutar: CPU uyusa bile ajan calismaya devam eder.
 * - START_STICKY: sistem oldururse yeniden baslatir.
 */
class AgentService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private val chId = "ajan_service"
    private val notifId = 42

    override fun onCreate() {
        super.onCreate()
        startForeground(notifId, buildNotification())
        acquireWakeLock()
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

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "ajan:agent"
        ).apply { setReferenceCounted(false); acquire() }
    }

    override fun onDestroy() {
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
AJEOF07

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/ReminderReceiver.kt << 'AJEOF08'
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
AJEOF08

cat > android/app/src/main/AndroidManifest.xml << 'AJEOF09'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET"/>
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
AJEOF09

rm -f android/app/src/main/kotlin/com/sametdemiral/ajan/AgentForegroundService.kt

echo "=== YAZILAN DOSYALAR ==="
wc -l lib/core/agent/llm_client.dart lib/core/tools/schedule_tools.dart android/app/src/main/kotlin/com/sametdemiral/ajan/*.kt android/app/src/main/AndroidManifest.xml
echo "=== BITTI. Simdi: git add -A && git commit -m v2 && git push ==="
