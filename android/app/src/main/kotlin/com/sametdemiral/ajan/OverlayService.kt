package com.sametdemiral.ajan

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * Ekran uzerinde duran yuzen baloncuk. Dokununca UYGULAMAYI ACMADAN, diger
 * uygulamalarin ustunde bir sohbet paneli acilir; buradan ajana yazip cevap
 * alinir (basssiz Flutter motoru + 'ajan/overlay' kanali).
 */
class OverlayService : Service() {
    private var wm: WindowManager? = null
    private var bubble: View? = null
    private var panel: View? = null

    private var channel: MethodChannel? = null

    private var responseView: TextView? = null
    private var inputView: EditText? = null
    private var sendBtn: Button? = null

    private val primary = Color.parseColor("#6C5CE7")
    private val bgCard = Color.parseColor("#1E1E2E")
    private val bgDeep = Color.parseColor("#11111B")

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        showBubble()
    }

    // --- Baloncuk ---

    private fun showBubble() {
        if (bubble != null) return
        val size = (56 * resources.displayMetrics.density).toInt()
        val view = FrameLayout(this).apply {
            addView(TextView(context).apply {
                text = "A"
                setTextColor(Color.WHITE)
                textSize = 22f
                gravity = Gravity.CENTER
            })
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(primary)
            }
        }

        val params = baseParams(size, size).apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            gravity = Gravity.TOP or Gravity.START
            x = 20; y = 300
        }

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
                    params.x = startX + dx; params.y = startY + dy
                    wm?.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) togglePanel()
                    true
                }
                else -> false
            }
        }
        bubble = view
        runCatching { wm?.addView(view, params) }
    }

    // --- Panel (sohbet) ---

    private fun togglePanel() {
        if (panel != null) {
            removePanel()
        } else {
            showPanel()
        }
    }

    private fun showPanel() {
        ensureEngine()
        val dp = resources.displayMetrics.density
        fun px(v: Int) = (v * dp).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(14), px(12), px(14), px(12))
            background = GradientDrawable().apply {
                cornerRadius = px(18).toFloat()
                setColor(bgDeep)
            }
        }

        // Baslik satiri
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(TextView(this).apply {
            text = "Ajan"
            setTextColor(Color.WHITE)
            textSize = 16f
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
        header.addView(TextView(this).apply {
            text = "Uygulama"
            setTextColor(Color.parseColor("#9E9CB8"))
            textSize = 12f
            setPadding(px(8), px(4), px(8), px(4))
            setOnClickListener { openApp() }
        })
        header.addView(TextView(this).apply {
            text = "  ✕"
            setTextColor(Color.parseColor("#9E9CB8"))
            textSize = 16f
            setOnClickListener { removePanel() }
        })
        root.addView(header)

        // Cevap alani (kaydirilabilir)
        responseView = TextView(this).apply {
            text = "Ne yapmami istersin? Yaz, ben cevaplayayim."
            setTextColor(Color.parseColor("#ECEBF7"))
            textSize = 14f
            setTextIsSelectable(true)
        }
        val scroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, px(220)).apply {
                topMargin = px(8); bottomMargin = px(8)
            }
            setPadding(px(10), px(10), px(10), px(10))
            background = GradientDrawable().apply {
                cornerRadius = px(12).toFloat()
                setColor(bgCard)
            }
            addView(responseView)
        }
        root.addView(scroll)

        // Giris satiri
        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        inputView = EditText(this).apply {
            hint = "Mesaj..."
            setHintTextColor(Color.parseColor("#6E6C8A"))
            setTextColor(Color.WHITE)
            textSize = 14f
            setPadding(px(12), px(10), px(12), px(10))
            background = GradientDrawable().apply {
                cornerRadius = px(20).toFloat()
                setColor(bgCard)
            }
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        sendBtn = Button(this).apply {
            text = "Gonder"
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                cornerRadius = px(20).toFloat()
                setColor(primary)
            }
            setOnClickListener { ask() }
        }
        inputRow.addView(inputView)
        inputRow.addView(sendBtn)
        root.addView(inputRow)

        val width = (resources.displayMetrics.widthPixels * 0.92).toInt()
        val params = baseParams(width, WindowManager.LayoutParams.WRAP_CONTENT).apply {
            // Odaklanabilir: EditText klavyesi acilsin.
            flags = WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            gravity = Gravity.BOTTOM
            y = px(40)
        }
        panel = root
        runCatching { wm?.addView(root, params) }
    }

    private fun removePanel() {
        panel?.let { runCatching { wm?.removeView(it) } }
        panel = null
        responseView = null
        inputView = null
        sendBtn = null
    }

    private fun ask() {
        val text = inputView?.text?.toString()?.trim() ?: ""
        if (text.isEmpty()) return
        if (channel == null) {
            responseView?.text = "Uygulama motoru hazir degil; uygulamayi bir kez ac ve tekrar dene."
            return
        }
        inputView?.setText("")
        responseView?.text = "Dusunuyorum..."
        sendBtn?.isEnabled = false
        channel?.invokeMethod("ask", text, object : MethodChannel.Result {
            override fun success(result: Any?) {
                responseView?.text = result?.toString() ?: "(bos cevap)"
                sendBtn?.isEnabled = true
            }
            override fun error(code: String, msg: String?, details: Any?) {
                responseView?.text = "Hata: $msg"
                sendBtn?.isEnabled = true
            }
            override fun notImplemented() {
                responseView?.text = "Islenemedi."
                sendBtn?.isEnabled = true
            }
        })
    }

    // --- Paylasimli (onbellekteki) motora baglan ---

    private fun ensureEngine() {
        if (channel != null) return
        val eng = FlutterEngineCache.getInstance().get(AjanApplication.ENGINE_ID)
        if (eng != null) {
            // Ana uygulamayla AYNI motor -> ayni ajan/sohbet.
            channel = MethodChannel(eng.dartExecutor.binaryMessenger, "ajan/overlay_in")
        }
    }

    private fun baseParams(w: Int, h: Int): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        return WindowManager.LayoutParams(w, h, type, 0, PixelFormat.TRANSLUCENT)
    }

    private fun openApp() {
        val i = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        if (i != null) startActivity(i)
        removePanel()
    }

    override fun onDestroy() {
        removePanel()
        bubble?.let { runCatching { wm?.removeView(it) } }
        bubble = null
        // Paylasimli motoru YOK ETME (uygulama kullaniyor); sadece referansi birak.
        channel = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
