package com.sametdemiral.ajan

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Alarmlarin tek kaynak-dogruluk deposu (native SharedPreferences) + zamanlama.
 *
 * Uygulama kapali olsa bile alarmlar AlarmManager.setAlarmClock ile calisir;
 * boot sonrasi BootReceiver ile yeniden kurulur. Dart tarafi sadece UI icin
 * bu listeyi okur/gunceller.
 */
object AlarmStore {
    private const val PREFS = "ajan_alarms"
    private const val KEY = "list"
    private const val SNOOZE_OFFSET = 100000
    const val SNOOZE_MINUTES = 5

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun loadArray(ctx: Context): JSONArray {
        val raw = prefs(ctx).getString(KEY, "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (e: Exception) {
            JSONArray()
        }
    }

    private fun saveArray(ctx: Context, arr: JSONArray) {
        prefs(ctx).edit().putString(KEY, arr.toString()).apply()
    }

    fun toJsonString(ctx: Context): String = loadArray(ctx).toString()

    private fun daysList(o: JSONObject): List<Int> {
        val out = mutableListOf<Int>()
        val a = o.optJSONArray("days") ?: JSONArray()
        for (i in 0 until a.length()) out.add(a.getInt(i))
        return out
    }

    private fun findIndex(arr: JSONArray, id: Int): Int {
        for (i in 0 until arr.length()) {
            if (arr.getJSONObject(i).getInt("id") == id) return i
        }
        return -1
    }

    // --- Dart'tan cagrilan islemler (hepsi guncel listeyi JSON dondurur) ---

    fun add(
        ctx: Context, hour: Int, minute: Int, label: String,
        days: List<Int>, vibrate: Boolean, sound: Boolean
    ): String {
        val arr = loadArray(ctx)
        var maxId = 0
        for (i in 0 until arr.length()) {
            maxId = maxOf(maxId, arr.getJSONObject(i).getInt("id"))
        }
        val id = maxId + 1
        val o = JSONObject().apply {
            put("id", id)
            put("hour", hour)
            put("minute", minute)
            put("label", label)
            put("days", JSONArray(days))
            put("enabled", true)
            put("vibrate", vibrate)
            put("sound", sound)
        }
        arr.put(o)
        saveArray(ctx, arr)
        scheduleOne(ctx, o)
        return arr.toString()
    }

    fun update(
        ctx: Context, id: Int, hour: Int, minute: Int, label: String,
        days: List<Int>, vibrate: Boolean, sound: Boolean
    ): String {
        val arr = loadArray(ctx)
        val idx = findIndex(arr, id)
        if (idx >= 0) {
            cancelOne(ctx, id)
            val o = arr.getJSONObject(idx)
            o.put("hour", hour)
            o.put("minute", minute)
            o.put("label", label)
            o.put("days", JSONArray(days))
            o.put("vibrate", vibrate)
            o.put("sound", sound)
            saveArray(ctx, arr)
            if (o.optBoolean("enabled", true)) scheduleOne(ctx, o)
        }
        return arr.toString()
    }

    fun delete(ctx: Context, id: Int): String {
        val arr = loadArray(ctx)
        val idx = findIndex(arr, id)
        if (idx >= 0) {
            cancelOne(ctx, id)
            arr.remove(idx)
            saveArray(ctx, arr)
        }
        return arr.toString()
    }

    fun setEnabled(ctx: Context, id: Int, enabled: Boolean): String {
        val arr = loadArray(ctx)
        val idx = findIndex(arr, id)
        if (idx >= 0) {
            val o = arr.getJSONObject(idx)
            o.put("enabled", enabled)
            saveArray(ctx, arr)
            if (enabled) scheduleOne(ctx, o) else cancelOne(ctx, id)
        }
        return arr.toString()
    }

    fun getById(ctx: Context, id: Int): JSONObject? {
        val arr = loadArray(ctx)
        val idx = findIndex(arr, id)
        return if (idx >= 0) arr.getJSONObject(idx) else null
    }

    // --- Zamanlama ---

    fun rescheduleAll(ctx: Context) {
        val arr = loadArray(ctx)
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.optBoolean("enabled", true)) scheduleOne(ctx, o)
        }
    }

    /** Tek seferlik alarm calinca tekrar calmasin diye kapatir. */
    fun disableOneShot(ctx: Context, id: Int) {
        val arr = loadArray(ctx)
        val idx = findIndex(arr, id)
        if (idx >= 0) {
            val o = arr.getJSONObject(idx)
            if (daysList(o).isEmpty()) {
                o.put("enabled", false)
                saveArray(ctx, arr)
            }
        }
    }

    fun nextTrigger(hour: Int, minute: Int, days: List<Int>): Long {
        val now = Calendar.getInstance()
        val base = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (days.isEmpty()) {
            if (base.timeInMillis <= now.timeInMillis) {
                base.add(Calendar.DAY_OF_YEAR, 1)
            }
            return base.timeInMillis
        }
        for (i in 0..7) {
            val c = base.clone() as Calendar
            c.add(Calendar.DAY_OF_YEAR, i)
            if (c.timeInMillis <= now.timeInMillis) continue
            if (days.contains(c.get(Calendar.DAY_OF_WEEK))) return c.timeInMillis
        }
        return base.timeInMillis
    }

    fun scheduleOne(ctx: Context, o: JSONObject) {
        val id = o.getInt("id")
        val trigger = nextTrigger(o.getInt("hour"), o.getInt("minute"), daysList(o))
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = firePendingIntent(ctx, id, snooze = false)
        val showPi = PendingIntent.getActivity(
            ctx, id,
            Intent(ctx, MainActivity::class.java),
            piFlags()
        )
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(trigger, showPi), pi)
        } catch (e: Exception) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
        }
    }

    /** Erteleme: verilen dakikada ayni alarmi tekrar caldirir. */
    fun scheduleSnooze(ctx: Context, id: Int, minutes: Int) {
        val trigger = System.currentTimeMillis() + minutes * 60_000L
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = firePendingIntent(ctx, id, snooze = true)
        try {
            am.setAlarmClock(
                AlarmManager.AlarmClockInfo(trigger,
                    PendingIntent.getActivity(ctx, id + SNOOZE_OFFSET,
                        Intent(ctx, MainActivity::class.java), piFlags())),
                pi
            )
        } catch (e: Exception) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
        }
    }

    fun cancelOne(ctx: Context, id: Int) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(firePendingIntent(ctx, id, snooze = false))
        am.cancel(firePendingIntent(ctx, id, snooze = true))
    }

    private fun firePendingIntent(ctx: Context, id: Int, snooze: Boolean): PendingIntent {
        val i = Intent(ctx, AlarmReceiver::class.java).apply {
            action = "com.sametdemiral.ajan.ALARM_FIRE"
            putExtra("id", id)
            putExtra("snooze", snooze)
        }
        val req = if (snooze) id + SNOOZE_OFFSET else id
        return PendingIntent.getBroadcast(ctx, req, i, piFlags())
    }

    private fun piFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT
}
