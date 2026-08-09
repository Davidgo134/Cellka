package com.github.davidgo134.cellka

import com.yandex.mapkit.MapKitFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Ключ прокидывается через BuildConfig из local.properties / env,
        // не хранится в репозитории.
        if (BuildConfig.MAPKIT_API_KEY.isNotEmpty()) {
            MapKitFactory.setApiKey(BuildConfig.MAPKIT_API_KEY)
        }
        super.configureFlutterEngine(flutterEngine)
        CellInfoPlugin.registerWith(flutterEngine, applicationContext)
    }
}
