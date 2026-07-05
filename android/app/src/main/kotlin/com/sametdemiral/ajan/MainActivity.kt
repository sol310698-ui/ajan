package com.sametdemiral.ajan

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val channel = "ajan/native"
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "termuxRun" -> {
                        val cmd = call.argument<String>("command") ?: ""
                        val timeout = call.argument<Int>("timeoutSec") ?: 60
                        runTermux(cmd, timeout, result)
                    }
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
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Termux'a RUN_COMMAND intent'i ile komut gonderir.
     * Cikti paylasilan bir dosyaya yazilir, sonra okunur (dosya-kopru yontemi).
     *
     * Gereksinim: Termux'ta allow-external-apps=true olmali.
     */
    private fun runTermux(command: String, timeoutSec: Int, result: MethodChannel.Result) {
        // Ciktinin yazilacagi ortak dosya (Termux HOME altinda).
        val outName = "ajan_out_${System.currentTimeMillis()}.txt"
        val termuxHome = "/data/data/com.termux/files/home"
        val outPath = "$termuxHome/$outName"
        // Uygulamamizin da okuyabilecegi paylasilan yol.
        val sharedOut = File(getExternalFilesDir(null), outName)

        // Komutu sarmala: stdout+stderr'i dosyaya yaz, sonra shared alana kopyala.
        val wrapped =
            "{ $command ; } > \"$outPath\" 2>&1 ; " +
            "cp \"$outPath\" \"${sharedOut.absolutePath}\" 2>/dev/null ; " +
            "cat \"$outPath\""

        val intent = Intent().apply {
            setClassName("com.termux", "com.termux.app.RunCommandService")
            action = "com.termux.RUN_COMMAND"
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", wrapped))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", termuxHome)
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0")
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            result.success("HATA: Termux baslatilamadi (${e.message}). " +
                "Termux kurulu mu ve allow-external-apps=true mi?")
            return
        }

        // Cikti dosyasini bekleyerek oku.
        scope.launch {
            val output = withContext(Dispatchers.IO) {
                val deadline = System.currentTimeMillis() + timeoutSec * 1000L
                var lastSize = -1L
                var stableCount = 0
                while (System.currentTimeMillis() < deadline) {
                    if (sharedOut.exists()) {
                        val size = sharedOut.length()
                        if (size == lastSize) {
                            stableCount++
                            // Boyut 2 kez ust uste ayni -> yazma bitti say.
                            if (stableCount >= 2) break
                        } else {
                            stableCount = 0
                            lastSize = size
                        }
                    }
                    delay(400)
                }
                if (sharedOut.exists()) {
                    val text = sharedOut.readText()
                    sharedOut.delete()
                    if (text.isBlank()) "(komut bitti, cikti yok)" else text
                } else {
                    "HATA: Cikti alinamadi (sure asimi veya izin). " +
                        "Termux ayarinda allow-external-apps=true olmali."
                }
            }
            result.success(output)
        }
    }

    private fun openApp(query: String, result: MethodChannel.Result) {
        val pm = packageManager
        // Once paket adi olarak dene.
        var launch = pm.getLaunchIntentForPackage(query)
        if (launch == null) {
            // Uygulama adiyla eslesme ara.
            val apps = pm.getInstalledApplications(0)
            val match = apps.firstOrNull {
                pm.getApplicationLabel(it).toString().equals(query, true) ||
                    pm.getApplicationLabel(it).toString().contains(query, true)
            }
            if (match != null) launch = pm.getLaunchIntentForPackage(match.packageName)
        }
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launch)
            result.success("acildi: $query")
        } else {
            result.success("bulunamadi: $query")
        }
    }

    private fun sendSms(number: String, message: String, result: MethodChannel.Result) {
        try {
            @Suppress("DEPRECATION")
            val sms = SmsManager.getDefault()
            sms.sendTextMessage(number, null, message, null, null)
            result.success("SMS gonderildi: $number")
        } catch (e: Exception) {
            result.success("SMS hatasi: ${e.message}")
        }
    }

    private fun notify(title: String, body: String, result: MethodChannel.Result) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val chId = "ajan_default"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(chId, "Ajan", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val n = NotificationCompat.Builder(this, chId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()
        nm.notify(System.currentTimeMillis().toInt(), n)
        result.success("bildirim gosterildi")
    }
}
