package com.sametdemiral.ajan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Cihaz yeniden baslatilinca (veya uygulama guncellenince) tum aktif
 * alarmlari yeniden kurar; boylece boot sonrasi alarmlar kaybolmaz.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                runCatching { AlarmStore.rescheduleAll(context) }
            }
        }
    }
}
