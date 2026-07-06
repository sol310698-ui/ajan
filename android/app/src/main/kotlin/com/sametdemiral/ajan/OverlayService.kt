package com.sametdemiral.ajan

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * Ekranin uzerinde duran yuzen buton (baloncuk). Her uygulamanin ustunde
 * gorunur; dokununca Ajan'i one getirir, surukleyerek tasinabilir.
 * "Diger uygulamalarin uzerinde goster" izni gerekir.
 */
class OverlayService : Service() {
    private var wm: WindowManager? = null
    private var bubble: View? = null

    override fun onCreate() {
        super.onCreate()
        showBubble()
    }

    private fun showBubble() {
        if (bubble != null) return
        wm = getSystemService(WINDOW_SERVICE) as WindowManager

        val size = (56 * resources.displayMetrics.density).toInt()
        val view = FrameLayout(this).apply {
            val tv = TextView(context).apply {
                text = "A"
                setTextColor(Color.WHITE)
                textSize = 22f
                gravity = Gravity.CENTER
            }
            addView(tv)
            setBackgroundColor(Color.parseColor("#6C5CE7"))
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            size, size, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = 300
        }

        // Suruklenebilir + tikla
        var startX = 0; var startY = 0
        var touchX = 0f; var touchY = 0f
        var moved = false
        view.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x; startY = params.y
                    touchX = e.rawX; touchY = e.rawY; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - touchX).toInt()
                    val dy = (e.rawY - touchY).toInt()
                    if (abs(dx) > 10 || abs(dy) > 10) moved = true
                    params.x = startX + dx
                    params.y = startY + dy
                    wm?.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) openApp()
                    true
                }
                else -> false
            }
        }

        bubble = view
        runCatching { wm?.addView(view, params) }
    }

    private fun openApp() {
        val i = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        if (i != null) startActivity(i)
    }

    override fun onDestroy() {
        bubble?.let { runCatching { wm?.removeView(it) } }
        bubble = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
