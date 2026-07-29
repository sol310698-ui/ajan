package com.sametdemiral.ajan

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Uygulama basladiginda TEK bir Flutter motoru olusturup onbellege koyar.
 * Hem ana ekran (MainActivity) hem de yuzen baloncuk (OverlayService) AYNI
 * motoru kullanir; boylece baloncuktan verilen komut, uygulamadaki ayni
 * ajan/sohbet uzerinde calisir.
 */
class AjanApplication : Application() {
    companion object {
        const val ENGINE_ID = "ajan_main"
    }

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }
}
