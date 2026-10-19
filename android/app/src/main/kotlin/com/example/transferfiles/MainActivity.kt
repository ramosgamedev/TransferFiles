package com.example.transferfiles

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.transferfiles/permissions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "requestStoragePermission") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    if (!Environment.isExternalStorageManager()) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.addCategory("android.intent.category.DEFAULT")
                            intent.data = Uri.parse(String.format("package:%s", applicationContext.packageName))
                            startActivityForResult(intent, 2296)
                            result.success(false)
                        } catch (e: Exception) {
                            val intent = Intent()
                            intent.action = Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION
                            startActivityForResult(intent, 2296)
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                } else {
                    // Meta Quest uses Android 12 (API 32), so it falls in the condition above.
                    result.success(true)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
