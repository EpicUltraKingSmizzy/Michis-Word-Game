package io.github.michiswordgame.michis_word_game

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Small native helpers the game calls over the "mwg/native" channel:
/// opening the phone's camera app, and keeping a hosted room alive while the
/// app is in the background (a foreground service).
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mwg/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "openCameraApp" -> result.success(openCameraApp())
                "startHosting" -> {
                    val code = call.argument<String>("code") ?: ""
                    result.success(startHosting(code))
                }
                "stopHosting" -> {
                    stopService(Intent(this, HostKeepAliveService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Opens the camera app in photo mode. Most Android camera apps (Google
    /// Camera, Samsung, Pixel) read QR codes in the viewfinder and offer to
    /// open the link, which brings the player back here via the app link.
    private fun openCameraApp(): Boolean {
        val intents = listOf(
            Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA),
            Intent(MediaStore.ACTION_IMAGE_CAPTURE),
        )
        for (i in intents) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        return false
    }

    private fun startHosting(code: String): Boolean {
        val intent = Intent(this, HostKeepAliveService::class.java).putExtra("code", code)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
