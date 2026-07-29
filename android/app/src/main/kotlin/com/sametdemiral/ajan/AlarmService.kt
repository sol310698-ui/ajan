package com.sametdemiral.ajan

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

/**
 * Alarm caldiginda calisan on plan servisi: sesi (dongulu) calar, titretir,
 * kilit ekrani ustunde acilan tam ekran bildirim gosterir. Durdur/Ertele
 * eylemlerini yonetir.
 */
class AlarmService : Service() {

    companion object {
        const val ACTION_START = "com.sametdemiral.ajan.ALARM_START"
        const val ACTION_STOP = "com.sametdemiral.ajan.ALARM_STOP"
        const val ACTION_SNOOZE = "com.sametdemiral.ajan.ALARM_SNOOZE"
        const val CHANNEL = "ajan_alarm"
        const val NOTIF_ID = 424242
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopEverything()
                return START_NOT_STICKY
            }
            ACTION_SNOOZE -> {
                val id = intent.getIntExtra("id", -1)
                if (id >= 0) {
                    AlarmStore.scheduleSnooze(this, id, AlarmStore.SNOOZE_MINUTES)
                }
                stopEverything()
                return START_NOT_STICKY
            }
            else -> {
                val id = intent?.getIntExtra("id", -1) ?: -1
                val label = intent?.getStringExtra("label") ?: ""
                val hour = intent?.getIntExtra("hour", 0) ?: 0
                val minute = intent?.getIntExtra("minute", 0) ?: 0
                val vibrate = intent?.getBooleanExtra("vibrate", true) ?: true
                val sound = intent?.getBooleanExtra("sound", true) ?: true
                startRinging(id, label, hour, minute, vibrate, sound)
            }
        }
        return START_STICKY
    }

    private fun startRinging(
        id: Int, label: String, hour: Int, minute: Int,
        vibrate: Boolean, sound: Boolean
    ) {
        ensureChannel()

        val timeText = String.format("%02d:%02d", hour, minute)

        val fullScreen = Intent(this, AlarmRingActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("id", id)
            putExtra("label", label)
            putExtra("time", timeText)
        }
        val fsFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        val fsPi = PendingIntent.getActivity(this, id, fullScreen, fsFlags)

        val stopPi = PendingIntent.getService(
            this, id + 1,
            Intent(this, AlarmService::class.java).setAction(ACTION_STOP),
            fsFlags
        )
        val snoozePi = PendingIntent.getService(
            this, id + 2,
            Intent(this, AlarmService::class.java)
                .setAction(ACTION_SNOOZE).putExtra("id", id),
            fsFlags
        )

        val title = if (label.isNotBlank()) label else "Alarm"
        val notif = NotificationCompat.Builder(this, CHANNEL)
            .setContentTitle(title)
            .setContentText("$timeText - Alarm caliyor")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fsPi, true)
            .setContentIntent(fsPi)
            .addAction(0, "Ertele (${AlarmStore.SNOOZE_MINUTES} dk)", snoozePi)
            .addAction(0, "Durdur", stopPi)
            .build()

        startForeground(NOTIF_ID, notif)

        // Tam ekran alarm ekranini DOGRUDAN da baslat (full-screen intent bazi
        // cihazlarda/OEM'lerde tetiklenmeyebiliyor; exact-alarm kaynakli FGS'ten
        // activity baslatmaya izin var).
        try {
            startActivity(fullScreen)
        } catch (e: Exception) {
            // olmazsa full-screen intent + bildirim yine de gosterir
        }

        if (sound) startSound()
        if (vibrate) startVibrate()
    }

    private fun startSound() {
        try {
            var uri: Uri? = RingtoneManager.getActualDefaultRingtoneUri(
                this, RingtoneManager.TYPE_ALARM)
            if (uri == null) {
                uri = RingtoneManager.getActualDefaultRingtoneUri(
                    this, RingtoneManager.TYPE_RINGTONE)
            }
            if (uri == null) return
            player = MediaPlayer().apply {
                setDataSource(this@AlarmService, uri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            // ses acilamazsa sessiz devam et
        }
    }

    private fun startVibrate() {
        val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        vibrator = vib
        val pattern = longArrayOf(0, 600, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(pattern, 0)
        }
    }

    private fun stopEverything() {
        try {
            player?.stop()
            player?.release()
        } catch (_: Exception) {}
        player = null
        try {
            vibrator?.cancel()
        } catch (_: Exception) {}
        vibrator = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(
                CHANNEL, "Alarm", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarm calma bildirimleri"
                setSound(null, null) // sesi biz calariz
                enableVibration(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }
    }

    override fun onDestroy() {
        stopEverything()
        super.onDestroy()
    }
}
