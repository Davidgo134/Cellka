package com.github.davidgo134.cellka

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // CellInfoPlugin — не FlutterPlugin: конструктор приватный,
        // канал поднимает companion-метод.
        CellInfoPlugin.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
