package com.sametdemiral.ajan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Alarm zamani gelince AlarmManager tarafindan tetiklenir (uygulama kapali
 * olsa bile). Calan servisi baslatir; tekrar eden alarmi bir sonraki gune
 * yeniden kurar, tek seferligi kapatir.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        val snooze = intent.getBooleanExtra("snooze", false)
        if (id < 0) return

        val alarm = AlarmStore.getById(context, id)
        val label = alarm?.optString("label") ?: ""
        val vibrate = alarm?.optBoolean("vibrate", true) ?: true
        val sound = alarm?.optBoolean("sound", true) ?: true
        val hour = alarm?.optInt("hour", 0) ?: 0
        val minute = alarm?.optInt("minute", 0) ?: 0

        // Calan servisi baslat.
        val svc = Intent(context, AlarmService::class.java).apply {
            action = AlarmService.ACTION_START
            putExtra("id", id)
            putExtra("label", label)
            putExtra("hour", hour)
            putExtra("minute", minute)
            putExtra("vibrate", vibrate)
            putExtra("sound", sound)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svc)
        } else {
            context.startService(svc)
        }

        // Erteleme calmasi degilse: tekrar edeni yeniden kur, tek seferligi kapat.
        if (!snooze && alarm != null) {
            val days = alarm.optJSONArray("days")
            if (days != null && days.length() > 0) {
                AlarmStore.scheduleOne(context, alarm)
            } else {
                AlarmStore.disableOneShot(context, id)
            }
        }
    }
}
