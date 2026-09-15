package com.example.scv_ptbg

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.provider.Settings

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ster/tablet_identity")
            .setMethodCallHandler { call, result ->
                if (call.method != "getTabletOrigin") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Read on this device, never from the copied SQLite database.
                // Android scopes this ID to the device, Android user and signing key.
                val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                if (id.isNullOrBlank() || !id.matches(Regex("[0-9a-fA-F]{16}")) ||
                    id == "0000000000000000" || id == "9774d56d682e549c") {
                    result.error("TABLET_ID_UNAVAILABLE", "No se pudo identificar esta tablet.", null)
                } else {
                    val model = Build.MODEL.replace(Regex("[^A-Za-z0-9_-]"), "_").take(40)
                    result.success("$model / ${id.lowercase()}")
                }
            }
    }
}
