package com.firoyang.helloknightrcc_server

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
import android.view.OrientationEventListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity: FlutterActivity() {
    private val MEDIA_SCANNER_CHANNEL = "com.firoyang.helloknightrcc_server/media_scanner"
    private val CAMERA2_CHANNEL = "com.firoyang.helloknightrcc_server/camera2"
    private val PREVIEW_STREAM_CHANNEL = "com.firoyang.helloknightrcc_server/preview_stream"
    private val FOREGROUND_SERVICE_CHANNEL = "com.firoyang.helloknightrcc_server/foreground_service"
    private val DEVICE_INFO_CHANNEL = "com.firoyang.helloknightrcc_server/device_info"
    private val ORIENTATION_CHANNEL = "com.firoyang.helloknightrcc_server/orientation"
    
    private var camera2Manager: Camera2Manager? = null
    private var previewStreamHandler: PreviewStreamHandler? = null
    private var orientationEventListener: OrientationEventListener? = null
    private var orientationEventSink: EventChannel.EventSink? = null
    private var currentOrientation: Int = 0

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
                    val videoQuality = call.argument<String>("videoQuality") ?: "ultra"
                    val enableAudio = call.argument<Boolean>("enableAudio") ?: true
                    val videoSize = call.argument<Map<*, *>>("videoSize") as? Map<String, Int>
                    val videoFpsRange = call.argument<Map<*, *>>("videoFpsRange") as? Map<String, Int>
                    if (outputPath != null) {
                        val success = camera2Manager?.startRecording(
                            outputPath, 
                            videoQuality, 
                            enableAudio,
                            videoSize,
                            videoFpsRange
                        ) ?: false
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
                "getCameraCapabilities" -> {
                    val cameraId = call.argument<String>("cameraId")
                    if (cameraId != null) {
                        val caps = camera2Manager?.getCameraCapabilities(cameraId)
                        result.success(caps)
                    } else {
                        result.error("INVALID_ARGUMENT", "cameraId is null", null)
                    }
                }
                "getAllCameraCapabilities" -> {
                    val caps = camera2Manager?.getAllCameraCapabilities()
                    result.success(caps)
                }
                "setOrientationLock" -> {
                    val locked = call.argument<Boolean>("locked") ?: true
                    camera2Manager?.setOrientationLock(locked)
                    Log.d("MainActivity", "方向锁定状态已设置: $locked")
                    result.success(true)
                }
                "setLockedRotationAngle" -> {
                    val angle = call.argument<Int>("angle") ?: 0
                    camera2Manager?.setLockedRotationAngle(angle)
                    Log.d("MainActivity", "锁定旋转角度已设置: $angle")
                    result.success(true)
                }
                "getOrientationStatus" -> {
                    val status = camera2Manager?.getOrientationStatus()
                    result.success(status)
                }
                "getPreviewSize" -> {
                    val size = camera2Manager?.getPreviewSize()
                    if (size != null) {
                        result.success(mapOf("width" to size.first, "height" to size.second))
                    } else {
                        result.success(mapOf("width" to 640, "height" to 480))
                    }
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
        
        // Device Info Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val deviceInfo = getDeviceInfo()
                    result.success(deviceInfo)
                }
                else -> result.notImplemented()
            }
        }
        
        // Orientation Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ORIENTATION_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    orientationEventSink = events
                    // 初始化时设置当前方向（默认为0，竖屏）
                    camera2Manager?.updateDeviceOrientation(0)
                    startOrientationListener()
                }
                
                override fun onCancel(arguments: Any?) {
                    stopOrientationListener()
                    orientationEventSink = null
                }
            }
        )
    }
    
    // 启动方向监听器
    private fun startOrientationListener() {
        if (orientationEventListener != null) {
            return
        }
        
        orientationEventListener = object : OrientationEventListener(this) {
            override fun onOrientationChanged(orientation: Int) {
                // 将方向转换为标准角度（0, 90, 180, 270）
                val normalizedOrientation = when {
                    orientation >= 315 || orientation < 45 -> 0      // 竖屏
                    orientation >= 45 && orientation < 135 -> 90      // 横屏右转
                    orientation >= 135 && orientation < 225 -> 180     // 倒置
                    orientation >= 225 && orientation < 315 -> 270    // 横屏左转
                    else -> 0
                }
                
                // 更新Camera2Manager的设备方向（无论是否改变都更新，用于解锁时计算方向）
                camera2Manager?.updateDeviceOrientation(normalizedOrientation)
                
                // 只在方向改变时发送事件
                if (normalizedOrientation != currentOrientation) {
                    currentOrientation = normalizedOrientation
                    Log.d("MainActivity", "设备方向改变: $currentOrientation 度")
                    // 发送方向变化事件到Flutter层
                    orientationEventSink?.success(currentOrientation)
                }
            }
        }
        
        if (orientationEventListener?.canDetectOrientation() == true) {
            orientationEventListener?.enable()
            Log.d("MainActivity", "方向监听器已启动")
        } else {
            Log.w("MainActivity", "设备不支持方向检测")
        }
    }
    
    // 停止方向监听器
    private fun stopOrientationListener() {
        orientationEventListener?.disable()
        orientationEventListener = null
        Log.d("MainActivity", "方向监听器已停止")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopOrientationListener()
    }
    
    // 获取设备信息
    private fun getDeviceInfo(): Map<String, String> {
        return mapOf(
            "model" to Build.MODEL,  // 设备型号，如 "AL-00"
            "manufacturer" to Build.MANUFACTURER,  // 制造商
            "brand" to Build.BRAND,  // 品牌
            "device" to Build.DEVICE,  // 设备代号
            "product" to Build.PRODUCT,  // 产品名称
            "androidVersion" to Build.VERSION.RELEASE,  // Android版本
            "sdkInt" to Build.VERSION.SDK_INT.toString(),  // SDK版本
        )
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

