package com.sametdemiral.ajan

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.ByteArrayOutputStream

/**
 * Ekranda gezinme + otomasyon: ekrani okur, metne dokunur, yazi yazar,
 * kaydirir, geri/ana ekran gibi genel islemleri yapar.
 *
 * MainActivity, statik [instance] uzerinden bu servisi cagirir.
 * Kullanici bunu bir kez Ayarlar > Erisilebilirlik > Ajan'dan acmali.
 */
class AjanAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: AjanAccessibilityService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    /** Ekrandaki gorunur metinleri toplayip dondurur (ajanin "gozu"). */
    fun readScreen(): String {
        val root = rootInActiveWindow ?: return "(ekran okunamadi)"
        val sb = StringBuilder()
        collectText(root, sb, 0)
        val out = sb.toString().trim()
        return if (out.isEmpty()) "(gorunur metin yok)" else out.take(4000)
    }

    private fun collectText(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 40) return
        val t = node.text?.toString()?.trim()
        val d = node.contentDescription?.toString()?.trim()
        val label = when {
            !t.isNullOrEmpty() -> t
            !d.isNullOrEmpty() -> d
            else -> null
        }
        if (label != null) {
            val tag = if (node.isClickable) "[tikla] " else ""
            sb.append(tag).append(label).append("\n")
        }
        for (i in 0 until node.childCount) {
            collectText(node.getChild(i), sb, depth + 1)
        }
    }

    /** Metni iceren ilk tiklanabilir ogeyi bulup tiklar. */
    fun tapText(target: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findByText(root, target) ?: return false
        var n: AccessibilityNodeInfo? = node
        while (n != null) {
            if (n.isClickable) {
                return n.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            n = n.parent
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun findByText(root: AccessibilityNodeInfo, target: String): AccessibilityNodeInfo? {
        val lower = target.lowercase()
        // Once dogrudan metin eslesmesi
        val hits = root.findAccessibilityNodeInfosByText(target)
        if (!hits.isNullOrEmpty()) return hits[0]
        // Sonra icerik aciklamasi / kismi eslesme
        return searchNode(root, lower)
    }

    private fun searchNode(node: AccessibilityNodeInfo?, lower: String): AccessibilityNodeInfo? {
        if (node == null) return null
        val t = node.text?.toString()?.lowercase()
        val d = node.contentDescription?.toString()?.lowercase()
        if ((t != null && t.contains(lower)) || (d != null && d.contains(lower))) return node
        for (i in 0 until node.childCount) {
            val r = searchNode(node.getChild(i), lower)
            if (r != null) return r
        }
        return null
    }

    /** Odaktaki (veya ilk) yazilabilir alana metin yazar. */
    fun setText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val field = findEditable(root) ?: return false
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun findEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable && node.isFocused) return node
        for (i in 0 until node.childCount) {
            val r = findEditable(node.getChild(i))
            if (r != null) return r
        }
        // odakli yoksa ilk yazilabiliri dene
        if (node.isEditable) return node
        return null
    }

    fun scroll(forward: Boolean): Boolean {
        val root = rootInActiveWindow ?: return false
        val s = findScrollable(root) ?: return false
        val action = if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        return s.performAction(action)
    }

    private fun findScrollable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val r = findScrollable(node.getChild(i))
            if (r != null) return r
        }
        return null
    }

    /**
     * Ekranin goruntusunu alir (API 30+), kucultup JPEG->base64 dondurur.
     * Erisilebilirlik agacinin yanlis/eksik okudugu durumlarda (ikonlar,
     * resimdeki yazi, yanlis etiketli butonlar) ajanin "gozu" olur.
     * Asenkron; sonucu [cb] ile doner (basarisizsa bos string).
     */
    fun takeShot(cb: (String) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            cb(""); return
        }
        try {
            takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                        try {
                            val buffer = result.hardwareBuffer
                            val raw = Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                            val bmp = raw?.copy(Bitmap.Config.ARGB_8888, false)
                            raw?.recycle()
                            buffer.close()
                            if (bmp == null) { cb(""); return }
                            val scaled = scaleDown(bmp, 900)
                            val baos = ByteArrayOutputStream()
                            scaled.compress(Bitmap.CompressFormat.JPEG, 70, baos)
                            if (scaled != bmp) scaled.recycle()
                            bmp.recycle()
                            cb(Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP))
                        } catch (e: Exception) {
                            cb("")
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        cb("")
                    }
                })
        } catch (e: Exception) {
            cb("")
        }
    }

    private fun scaleDown(bmp: Bitmap, maxSide: Int): Bitmap {
        val w = bmp.width
        val h = bmp.height
        val longest = maxOf(w, h)
        if (longest <= maxSide) return bmp
        val ratio = maxSide.toFloat() / longest
        return Bitmap.createScaledBitmap(
            bmp, (w * ratio).toInt(), (h * ratio).toInt(), true)
    }

    fun doGlobal(action: String): Boolean {
        val a = when (action) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            else -> return false
        }
        return performGlobalAction(a)
    }
}
