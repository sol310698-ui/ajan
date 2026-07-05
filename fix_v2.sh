#!/data/data/com.termux/files/usr/bin/bash
# Ajan v2 duzeltme: eksik metotlar + wakelock tutarliligi
set -e
cd ~/ajan_repo

cat > lib/core/native/native_tools.dart << 'FIXEOF1'
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
FIXEOF1

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/MainActivity.kt << 'FIXEOF2'
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
FIXEOF2

cat > android/app/src/main/kotlin/com/sametdemiral/ajan/AgentService.kt << 'FIXEOF3'
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
FIXEOF3

echo "=== Duzeltildi ==="
wc -l lib/core/native/native_tools.dart android/app/src/main/kotlin/com/sametdemiral/ajan/MainActivity.kt android/app/src/main/kotlin/com/sametdemiral/ajan/AgentService.kt
