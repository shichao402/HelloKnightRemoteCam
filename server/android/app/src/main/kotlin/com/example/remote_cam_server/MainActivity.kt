package com.example.remote_cam_server

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.hardware.camera2.CameraManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity: FlutterActivity() {
    private val MEDIA_SCANNER_CHANNEL = "com.example.remote_cam_server/media_scanner"
    private val CAMERA2_CHANNEL = "com.example.remote_cam_server/camera2"
    private val PREVIEW_STREAM_CHANNEL = "com.example.remote_cam_server/preview_stream"
    
    private var camera2Manager: Camera2Manager? = null
    private var previewStreamHandler: PreviewStreamHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Media Scanner Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SCANNER_CHANNEL).setMethodCallHandler { call, result ->
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
        
        // Camera2 Channel
        camera2Manager = Camera2Manager(this)
        previewStreamHandler = PreviewStreamHandler()
        previewStreamHandler?.setCamera2Manager(camera2Manager)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA2_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val cameraId = call.argument<String>("cameraId") ?: "0"
                    val previewWidth = call.argument<Int>("previewWidth") ?: 640
                    val previewHeight = call.argument<Int>("previewHeight") ?: 480
                    
                    // 使用协程调用suspend函数
                    CoroutineScope(Dispatchers.Main).launch {
                        try {
                            val success = camera2Manager?.initialize(cameraId, previewWidth, previewHeight) ?: false
                            if (success) {
                                // PreviewStreamHandler会自动设置回调（在onListen或setCamera2Manager中）
                                Log.d("MainActivity", "相机初始化成功，预览帧回调将由PreviewStreamHandler管理")
                            }
                            result.success(success)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "初始化相机异常", e)
                            result.error("INIT_ERROR", e.message, null)
                        }
                    }
                }
                "startRecording" -> {
                    val outputPath = call.argument<String>("outputPath")
                    if (outputPath != null) {
                        val success = camera2Manager?.startRecording(outputPath) ?: false
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "outputPath is null", null)
                    }
                }
                "stopRecording" -> {
                    val path = camera2Manager?.stopRecording()
                    result.success(path)
                }
                "takePicture" -> {
                    val outputPath = call.argument<String>("outputPath")
                    if (outputPath != null) {
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val path = camera2Manager?.takePicture(outputPath)
                                result.success(path)
                            } catch (e: Exception) {
                                Log.e("MainActivity", "拍照异常", e)
                                result.error("CAPTURE_ERROR", e.message, null)
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "outputPath is null", null)
                    }
                }
                "release" -> {
                    camera2Manager?.release()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Preview Stream Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PREVIEW_STREAM_CHANNEL).setStreamHandler(previewStreamHandler)
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

