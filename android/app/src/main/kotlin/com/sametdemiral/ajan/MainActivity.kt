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
