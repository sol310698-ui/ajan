package com.sametdemiral.ajan

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.Settings
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
        // Genisletilmis cihaz araclari icin tehlikeli izinler.
        for (p in listOf(
            "android.permission.READ_CONTACTS",
            "android.permission.READ_SMS",
            "android.permission.CALL_PHONE"
        )) {
            if (checkSelfPermission(p) != PackageManager.PERMISSION_GRANTED) want.add(p)
        }
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
                    "screenshot" -> {
                        val svc = AjanAccessibilityService.instance
                        if (svc == null) {
                            result.success("")
                        } else {
                            svc.takeShot { b64 -> main.post { result.success(b64) } }
                        }
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
                    "clipboardGet" -> result.success(clipboardGet())
                    "clipboardSet" -> {
                        clipboardSet(call.argument<String>("text") ?: "")
                        result.success("panoya kopyalandi")
                    }
                    "batteryStatus" -> result.success(batteryStatus())
                    "deviceInfo" -> result.success(deviceInfo())
                    "toggleTorch" ->
                        result.success(toggleTorch(call.argument<Boolean>("on") ?: true))
                    "makeCall" -> result.success(makeCall(call.argument<String>("number") ?: ""))
                    "readContacts" ->
                        result.success(readContacts(call.argument<String>("query") ?: ""))
                    "readSms" -> result.success(readSms(call.argument<Int>("limit") ?: 10))
                    "addCalendarEvent" -> result.success(addCalendarEvent(
                        call.argument<String>("title") ?: "Etkinlik",
                        call.argument<String>("description") ?: "",
                        (call.argument<Number>("start")?.toLong()) ?: System.currentTimeMillis(),
                        (call.argument<Number>("end")?.toLong())
                            ?: (System.currentTimeMillis() + 3600000L)
                    ))
                    "listApps" -> result.success(listApps())
                    "setVolume" -> result.success(setVolume(call.argument<Int>("percent") ?: 50))
                    "vibrate" -> result.success(vibrate(call.argument<Int>("ms") ?: 400))
                    "openUrl" -> result.success(openUrl(call.argument<String>("url") ?: ""))
                    "openSettings" ->
                        result.success(openSettings(call.argument<String>("panel") ?: "settings"))
                    "scheduleWake" -> {
                        scheduleWake((call.argument<Number>("delayMillis")?.toLong()) ?: 60000L)
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
        // Bildirime basinca uygulamayi ac.
        val launch = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT
        val contentPi = PendingIntent.getActivity(
            this, System.currentTimeMillis().toInt(), launch, piFlags)

        val n = NotificationCompat.Builder(this, chId)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(contentPi)
            .setAutoCancel(true)
            .build()
        nm.notify(System.currentTimeMillis().toInt(), n)
        result.success("bildirim gosterildi")
    }

    // --- Genisletilmis cihaz araclari ---

    private fun clipboardGet(): String {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = cm.primaryClip ?: return ""
        if (clip.itemCount == 0) return ""
        return clip.getItemAt(0).coerceToText(this).toString()
    }

    private fun clipboardSet(text: String) {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("ajan", text))
    }

    private fun batteryStatus(): String {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        return "Batarya: %$level, ${if (charging) "sarj oluyor" else "sarj olmuyor"}"
    }

    private fun deviceInfo(): String {
        val dm = resources.displayMetrics
        return buildString {
            append("Uretici: ${Build.MANUFACTURER}\n")
            append("Model: ${Build.MODEL}\n")
            append("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})\n")
            append("Ekran: ${dm.widthPixels}x${dm.heightPixels} @${dm.densityDpi}dpi")
        }
    }

    private fun toggleTorch(on: Boolean): String {
        return try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = cm.cameraIdList.firstOrNull { camId ->
                cm.getCameraCharacteristics(camId)
                    .get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: return "El feneri bulunamadi."
            cm.setTorchMode(id, on)
            if (on) "el feneri acildi" else "el feneri kapatildi"
        } catch (e: Exception) {
            "el feneri hatasi: ${e.message}"
        }
    }

    private fun makeCall(number: String): String {
        if (number.isBlank()) return "HATA: numara bos."
        val uri = Uri.parse("tel:$number")
        return try {
            if (checkSelfPermission("android.permission.CALL_PHONE")
                == PackageManager.PERMISSION_GRANTED) {
                startActivity(Intent(Intent.ACTION_CALL, uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "araniyor: $number"
            } else {
                startActivity(Intent(Intent.ACTION_DIAL, uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "arama ekrani acildi: $number (arama iznini ver, otomatik arasin)"
            }
        } catch (e: Exception) {
            "arama hatasi: ${e.message}"
        }
    }

    private fun readContacts(query: String): String {
        if (checkSelfPermission("android.permission.READ_CONTACTS")
            != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf("android.permission.READ_CONTACTS"), reqRunCommand)
            return "Rehber izni henuz yok; izin penceresinden ver ve tekrar dene."
        }
        val out = StringBuilder()
        val proj = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER
        )
        val sel = if (query.isBlank()) null
            else "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
        val args = if (query.isBlank()) null else arrayOf("%$query%")
        val cursor = contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI, proj, sel, args,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC")
        cursor?.use {
            var n = 0
            while (it.moveToNext() && n < 30) {
                out.append("${it.getString(0)}: ${it.getString(1)}\n")
                n++
            }
        }
        return out.toString().trim()
    }

    private fun readSms(limit: Int): String {
        if (checkSelfPermission("android.permission.READ_SMS")
            != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf("android.permission.READ_SMS"), reqRunCommand)
            return "SMS okuma izni henuz yok; izin penceresinden ver ve tekrar dene."
        }
        val out = StringBuilder()
        val cursor = contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("address", "body", "date"), null, null, "date DESC")
        cursor?.use {
            var n = 0
            while (it.moveToNext() && n < limit) {
                out.append("${it.getString(0)}: ${it.getString(1)}\n")
                n++
            }
        }
        return out.toString().trim()
    }

    private fun addCalendarEvent(
        title: String, desc: String, start: Long, end: Long): String {
        return try {
            val i = Intent(Intent.ACTION_INSERT)
                .setData(CalendarContract.Events.CONTENT_URI)
                .putExtra(CalendarContract.Events.TITLE, title)
                .putExtra(CalendarContract.Events.DESCRIPTION, desc)
                .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
                .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
            "takvim etkinligi hazirlandi: $title (kaydetmek icin onayla)"
        } catch (e: Exception) {
            "takvim hatasi: ${e.message}"
        }
    }

    private fun listApps(): String {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = pm.queryIntentActivities(intent, 0)
            .map { it.loadLabel(pm).toString() }
            .distinct()
            .sorted()
        return apps.joinToString(", ")
    }

    private fun setVolume(percent: Int): String {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val v = (max * percent.coerceIn(0, 100) / 100.0).toInt()
        am.setStreamVolume(AudioManager.STREAM_MUSIC, v, 0)
        return "medya sesi %$percent yapildi"
    }

    private fun vibrate(ms: Int): String {
        val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vib.vibrate(VibrationEffect.createOneShot(
                ms.toLong(), VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(ms.toLong())
        }
        return "titredildi ($ms ms)"
    }

    private fun openUrl(url: String): String {
        return try {
            val u = if (url.startsWith("http")) url else "https://$url"
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            "acildi: $u"
        } catch (e: Exception) {
            "acilamadi: ${e.message}"
        }
    }

    private fun openSettings(panel: String): String {
        val action = when (panel.lowercase()) {
            "wifi" -> Settings.ACTION_WIFI_SETTINGS
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
            "battery" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
            "sound" -> Settings.ACTION_SOUND_SETTINGS
            "display" -> Settings.ACTION_DISPLAY_SETTINGS
            "apps" -> Settings.ACTION_APPLICATION_SETTINGS
            "data" -> Settings.ACTION_DATA_ROAMING_SETTINGS
            "nfc" -> Settings.ACTION_NFC_SETTINGS
            "airplane" -> Settings.ACTION_AIRPLANE_MODE_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        return try {
            startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            "ayar ekrani acildi: $panel"
        } catch (e: Exception) {
            "ayar acilamadi: ${e.message}"
        }
    }

    private fun scheduleWake(delayMillis: Long) {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val i = Intent(this, WakeReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getBroadcast(this, 7777, i, flags)
        val at = System.currentTimeMillis() + delayMillis
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: SecurityException) {
            am.set(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    override fun onDestroy() {
        receiver?.let { runCatching { unregisterReceiver(it) } }
        releaseWakeLock()
        super.onDestroy()
    }
}
