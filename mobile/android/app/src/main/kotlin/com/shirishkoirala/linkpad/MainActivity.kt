package com.shirishkoirala.linkpad

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private var keepScreenAwake = false
    private var screenResumed = false
    private fun updateScreenAwake() {
        if (keepScreenAwake && screenResumed && hasWindowFocus()) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) { super.onWindowFocusChanged(hasFocus); updateScreenAwake() }
    override fun onResume() { super.onResume(); screenResumed = true; updateScreenAwake() }
    override fun onPause() { screenResumed = false; window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); super.onPause() }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linkpad/screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setKeepScreenAwake") {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled == null) result.error("invalid", "An enabled value is required.", null)
                    else { keepScreenAwake = enabled; updateScreenAwake(); result.success(null) }
                } else { result.notImplemented() }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linkpad/permissions")
            .setMethodCallHandler { call, result ->
                if (call.method == "openSettings") {
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")))
                        result.success(true)
                    } catch (error: Exception) { result.success(false) }
                } else { result.notImplemented() }
            }
    }
}
