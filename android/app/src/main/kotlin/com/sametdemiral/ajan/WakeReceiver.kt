package com.sametdemiral.ajan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Rutin zamani gelince AlarmManager tarafindan tetiklenir. Uygulamayi
 * (arka planda / singleTop) one getirir; boylece Dart tarafindaki rutin
 * zamanlayicisi vadesi gelen otonom gorevleri calistirabilir.
 *
 * Not: Cihaz kilitliyken arka plandan Activity baslatma bazi surumlerde
 * kisitlidir; en azindan uygulama surecini canli tutmaya ve zamanlayiciyi
 * tetiklemeye yarar.
 */
class WakeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        runCatching {
            val i = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            context.startActivity(i)
        }
        // Uygulama zaten acikken de on plan servisi surecin canli kalmasini
        // saglar; ek islem gerekmez.
    }
}
