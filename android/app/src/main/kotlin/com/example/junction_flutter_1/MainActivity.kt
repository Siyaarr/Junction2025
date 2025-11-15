package com.example.junction_flutter_1

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.junction_flutter_1/settings"
    private val WAKE_CHANNEL = "com.example.junction_flutter_1/app_wake"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Set up method channel for opening app settings
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openAppSettings") {
                try {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", packageName, null)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to open app settings: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Set up method channel for bringing app to foreground
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "bringToForeground") {
                try {
                    // Wake up and unlock screen if needed (do this immediately)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        runOnUiThread {
                            setShowWhenLocked(true)
                            setTurnScreenOn(true)
                        }
                    } else {
                        runOnUiThread {
                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                            )
                        }
                    }
                    
                    // Bring the activity to foreground IMMEDIATELY (don't wait for UI thread)
                    val intent = Intent(this@MainActivity, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT
                    }
                    startActivity(intent)
                    
                    // Move task to front using ActivityManager (try immediately, don't wait)
                    try {
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        activityManager.moveTaskToFront(taskId, 0) // Use 0 instead of MOVE_TASK_WITH_HOME for faster execution
                    } catch (e: Exception) {
                        // If moveTaskToFront fails, the intent flags should still work
                        android.util.Log.w("MainActivity", "Could not move task to front: ${e.message}")
                    }
                    
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to bring app to foreground: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
