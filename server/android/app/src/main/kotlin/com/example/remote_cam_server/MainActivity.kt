package com.example.remote_cam_server

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.provider.MediaStore
import android.hardware.camera2.CameraManager
import android.util.Log
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ThumbnailUtils
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
    private val FOREGROUND_SERVICE_CHANNEL = "com.example.remote_cam_server/foreground_service"
    
    private var camera2Manager: Camera2Manager? = null
    private var previewStreamHandler: PreviewStreamHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Media Scanner Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SCANNER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        scanMediaFile(filePath)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is null", null)
                    }
                }
                "getVideoThumbnail" -> {
                    val videoPath = call.argument<String>("videoPath")
                    if (videoPath != null) {
                        val thumbnailPath = getVideoThumbnail(videoPath)
                        result.success(thumbnailPath)
                    } else {
                        result.error("INVALID_ARGUMENT", "videoPath is null", null)
                    }
                }
                "getImageThumbnail" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath != null) {
                        val thumbnailPath = getImageThumbnail(imagePath)
                        result.success(thumbnailPath)
                    } else {
                        result.error("INVALID_ARGUMENT", "imagePath is null", null)
                    }
                }
                else -> result.notImplemented()
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
                "resumePreview" -> {
                    camera2Manager?.resumePreview()
                    result.success(null)
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
        
        // Foreground Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOREGROUND_SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    CameraForegroundService.startService(this)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    CameraForegroundService.stopService(this)
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val isIgnoring = isIgnoringBatteryOptimizations()
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                else -> result.notImplemented()
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

    // 检查是否已忽略电池优化
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            return powerManager.isIgnoringBatteryOptimizations(packageName)
        }
        return true // Android 6.0以下不需要
    }

    // 请求忽略电池优化
    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    // 如果无法直接请求，引导用户到设置页面
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                    } catch (e2: Exception) {
                        Log.e("MainActivity", "无法打开电池优化设置", e2)
                    }
                }
            }
        }
    }

    // 获取视频缩略图
    private fun getVideoThumbnail(videoPath: String): String? {
        try {
            val file = java.io.File(videoPath)
            if (!file.exists()) {
                Log.w("MainActivity", "视频文件不存在: $videoPath")
                return null
            }

            // 使用ThumbnailUtils创建视频缩略图
            val thumbnail: Bitmap? = ThumbnailUtils.createVideoThumbnail(
                videoPath,
                MediaStore.Video.Thumbnails.MINI_KIND
            )

            if (thumbnail == null) {
                Log.w("MainActivity", "无法生成视频缩略图: $videoPath")
                return null
            }

            // 保存缩略图到临时文件
            val thumbnailDir = java.io.File(cacheDir, "thumbnails")
            if (!thumbnailDir.exists()) {
                thumbnailDir.mkdirs()
            }

            val thumbnailFile = java.io.File(thumbnailDir, "${file.nameWithoutExtension}.jpg")
            thumbnailFile.outputStream().use { out ->
                thumbnail.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }

            thumbnail.recycle()

            Log.d("MainActivity", "视频缩略图已生成: ${thumbnailFile.absolutePath}")
            return thumbnailFile.absolutePath
        } catch (e: Exception) {
            Log.e("MainActivity", "获取视频缩略图失败", e)
            return null
        }
    }

    // 获取照片缩略图
    private fun getImageThumbnail(imagePath: String): String? {
        try {
            val file = java.io.File(imagePath)
            if (!file.exists()) {
                Log.w("MainActivity", "图片文件不存在: $imagePath")
                return null
            }

            // 读取图片并生成缩略图
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(imagePath, options)

            // 计算缩放比例
            val reqWidth = 400
            val reqHeight = 400
            var inSampleSize = 1
            if (options.outHeight > reqHeight || options.outWidth > reqWidth) {
                val halfHeight = options.outHeight / 2
                val halfWidth = options.outWidth / 2
                while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                    inSampleSize *= 2
                }
            }

            // 加载缩略图
            val thumbnailOptions = BitmapFactory.Options().apply {
                inSampleSize = inSampleSize
            }
            val thumbnail = BitmapFactory.decodeFile(imagePath, thumbnailOptions)
            if (thumbnail == null) {
                Log.w("MainActivity", "无法生成图片缩略图: $imagePath")
                return null
            }

            // 保存缩略图到临时文件
            val thumbnailDir = java.io.File(cacheDir, "thumbnails")
            if (!thumbnailDir.exists()) {
                thumbnailDir.mkdirs()
            }

            val thumbnailFile = java.io.File(thumbnailDir, "${file.nameWithoutExtension}.jpg")
            thumbnailFile.outputStream().use { out ->
                thumbnail.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }

            thumbnail.recycle()

            Log.d("MainActivity", "图片缩略图已生成: ${thumbnailFile.absolutePath}")
            return thumbnailFile.absolutePath
        } catch (e: Exception) {
            Log.e("MainActivity", "获取图片缩略图失败", e)
            return null
        }
    }
}

