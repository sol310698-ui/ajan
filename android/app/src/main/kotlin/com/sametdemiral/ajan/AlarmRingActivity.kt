package com.sametdemiral.ajan

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Alarm calarken kilit ekrani ustunde acilan tam ekran. Buyuk saat + etiket +
 * Durdur / Ertele butonlari. Butonlar AlarmService'e komut gonderir.
 */
class AlarmRingActivity : Activity() {

    private var alarmId = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Kilitliyken goster + ekrani uyandir.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        alarmId = intent.getIntExtra("id", -1)
        val label = intent.getStringExtra("label") ?: ""
        val time = intent.getStringExtra("time") ?: ""

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0A0A0F"))
            setPadding(48, 48, 48, 48)
        }

        val icon = TextView(this).apply {
            text = "⏰"
            textSize = 64f
            gravity = Gravity.CENTER
        }
        val timeView = TextView(this).apply {
            text = time
            setTextColor(Color.WHITE)
            textSize = 72f
            gravity = Gravity.CENTER
        }
        val labelView = TextView(this).apply {
            text = if (label.isBlank()) "Alarm" else label
            setTextColor(Color.parseColor("#9E9CB8"))
            textSize = 22f
            gravity = Gravity.CENTER
        }

        val snooze = Button(this).apply {
            text = "Ertele (${AlarmStore.SNOOZE_MINUTES} dk)"
            setOnClickListener { sendAction(AlarmService.ACTION_SNOOZE); finishAndRemove() }
        }
        val stop = Button(this).apply {
            text = "Durdur"
            setBackgroundColor(Color.parseColor("#6C5CE7"))
            setTextColor(Color.WHITE)
            setOnClickListener { sendAction(AlarmService.ACTION_STOP); finishAndRemove() }
        }

        val spacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 60)
        }
        val spacer2 = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 24)
        }

        root.addView(icon)
        root.addView(timeView)
        root.addView(labelView)
        root.addView(spacer)
        root.addView(snooze)
        root.addView(spacer2)
        root.addView(stop)
        setContentView(root)
    }

    private fun sendAction(action: String) {
        val i = Intent(this, AlarmService::class.java)
            .setAction(action)
            .putExtra("id", alarmId)
        startService(i)
    }

    private fun finishAndRemove() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            finish()
        }
    }
}
