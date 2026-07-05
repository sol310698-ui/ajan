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
