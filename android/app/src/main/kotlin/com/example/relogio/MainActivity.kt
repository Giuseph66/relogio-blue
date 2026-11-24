package com.example.relogio

import android.annotation.SuppressLint
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "geonexo/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceId") result.success(deviceId()) else result.notImplemented()
            }
    }

    // Stable for this phone + signing key, even after reinstalling. Only its
    // hash leaves the phone. (Real MAC addresses are hidden since Android 6.)
    @SuppressLint("HardwareIds")
    private fun deviceId(): String? {
        val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        if (id.isNullOrEmpty()) return null
        val hash = MessageDigest.getInstance("SHA-256").digest("geonexo:$id".toByteArray())
        return "android-" + hash.joinToString("") { "%02x".format(it) }
    }
}
