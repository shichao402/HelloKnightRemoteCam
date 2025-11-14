package com.example.remote_cam_server

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.remote_cam_server/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    scanMediaFile(filePath)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "filePath is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun scanMediaFile(filePath: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ 使用 MediaStore API
                val file = java.io.File(filePath)
                val fileName = file.name
                val isVideo = fileName.endsWith(".mp4", ignoreCase = true) || 
                             fileName.endsWith(".mov", ignoreCase = true) ||
                             fileName.endsWith(".avi", ignoreCase = true)
                
                val contentUri = if (isVideo) {
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                } else {
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                }
                
                val relativePath = if (isVideo) {
                    "Movies/RemoteCam"
                } else {
                    "Pictures/RemoteCam"
                }
                
                val values = android.content.ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                
                val uri = contentResolver.insert(contentUri, values)
                if (uri != null) {
                    // 复制文件内容
                    contentResolver.openOutputStream(uri)?.use { output ->
                        file.inputStream().use { input ->
                            input.copyTo(output)
                        }
                    }
                    
                    // 标记为完成
                    val updateValues = android.content.ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }
                    contentResolver.update(uri, updateValues, null, null)
                }
            } else {
                // Android 9 及以下使用广播
                val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                intent.data = Uri.parse("file://$filePath")
                sendBroadcast(intent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}

