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
