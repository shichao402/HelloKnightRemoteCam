package com.example.remote_cam_server

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.hardware.camera2.CameraCaptureSession.CaptureCallback
import android.media.CamcorderProfile
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.TimeoutCancellationException

class Camera2Manager(private val context: Context) {
    private val TAG = "Camera2Manager"
    
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var mediaRecorder: MediaRecorder? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    
    private var isRecording = false
    private var currentVideoPath: String? = null
    private var recordingStartTime: Long = 0
    private var recordingSessionResult: CompletableDeferred<Boolean>? = null
    private var sessionCloseResult: CompletableDeferred<Unit>? = null
    
    private val cameraOpenCloseLock = Semaphore(1)
    private var initializationResult: CompletableDeferred<Boolean>? = null
    private var sessionCreationResult: CompletableDeferred<Boolean>? = null
    
    // 拍照相关
    private var jpegImageReader: ImageReader? = null
    private var pictureResult: CompletableDeferred<String?>? = null
    
    // 预览帧回调
    var previewFrameCallback: ((ByteArray) -> Unit)? = null
    
    // 持久化Surface（用于兼容性）
    private var persistentSurface: Surface? = null
    
    // 方向锁定状态（true=锁定，使用固定方向；false=解锁，使用重力感应）
    @Volatile
    private var orientationLocked: Boolean = true // 默认锁定
    
    // 当前设备方向（用于解锁时计算JPEG方向）
    @Volatile
    private var currentDeviceOrientation: Int = 0
    
    // 锁定状态下的手动旋转角度（0, 90, 180, 270度）
    @Volatile
    private var lockedRotationAngle: Int = 0 // 默认0度（竖屏）
    
    // 实际选择的预览尺寸
    @Volatile
    private var actualPreviewWidth: Int = 640
    @Volatile
    private var actualPreviewHeight: Int = 480
    
    // 相机传感器方向（在初始化时获取）
    @Volatile
    private var sensorOrientation: Int = 0
    
    suspend fun initialize(cameraId: String, previewWidth: Int, previewHeight: Int): Boolean {
        try {
            Log.d(TAG, "开始初始化相机，相机ID: $cameraId, 预览尺寸: ${previewWidth}x${previewHeight}")
            initializationResult = CompletableDeferred()
            
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            Log.d(TAG, "获取相机管理器成功")
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            Log.d(TAG, "获取相机特性成功")
            
            // 获取并保存传感器方向
            sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            Log.d(TAG, "传感器方向: $sensorOrientation 度")
            
            // 获取支持的输出尺寸
            val streamConfigurationMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val previewSizes = streamConfigurationMap?.getOutputSizes(ImageFormat.YUV_420_888)
            
            // 选择预览尺寸
            val previewSize = if (previewSizes == null || previewSizes.isEmpty()) {
                Log.e(TAG, "无法找到合适的预览尺寸")
                null
            } else if (previewWidth == 640 && previewHeight == 480) {
                // 如果传入的是默认值640x480，选择最大的预览尺寸（但不超过1920x1080）
                previewSizes.filter { 
                    it.width <= 1920 && it.height <= 1080 
                }.maxByOrNull { 
                    it.width * it.height 
                } ?: previewSizes.first()
            } else {
                // 使用传入的尺寸，选择最接近的尺寸（小于等于传入尺寸的最大尺寸）
                previewSizes.filter { 
                    it.width <= previewWidth && it.height <= previewHeight 
                }.maxByOrNull { 
                    it.width * it.height 
                } ?: previewSizes.first()
            }
            
            if (previewSize == null) {
                Log.e(TAG, "无法找到合适的预览尺寸")
                initializationResult?.complete(false)
                return false
            }
            
            Log.d(TAG, "选择预览尺寸: ${previewSize.width}x${previewSize.height} (请求尺寸: ${previewWidth}x${previewHeight})")
            
            // 保存实际选择的预览尺寸
            actualPreviewWidth = previewSize.width
            actualPreviewHeight = previewSize.height
            
            // 先启动后台线程，确保backgroundHandler已初始化
            startBackgroundThread()
            
            // 创建ImageReader用于预览
            imageReader = ImageReader.newInstance(
                previewSize.width,
                previewSize.height,
                ImageFormat.YUV_420_888,
                2
            )
            
            imageReader?.setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage()
                if (image != null) {
                    processPreviewImage(image)
                    image.close()
                }
            }, backgroundHandler)
            
            // 创建JPEG ImageReader用于拍照（使用最大分辨率）
            val jpegSizes = streamConfigurationMap?.getOutputSizes(ImageFormat.JPEG)
            val jpegSize = jpegSizes?.maxByOrNull { it.width * it.height } ?: android.util.Size(1920, 1080)
            Log.d(TAG, "选择拍照尺寸: ${jpegSize.width}x${jpegSize.height}")
            
            jpegImageReader = ImageReader.newInstance(
                jpegSize.width,
                jpegSize.height,
                ImageFormat.JPEG,
                1
            )
            
            jpegImageReader?.setOnImageAvailableListener({ reader ->
                try {
                    val image = reader.acquireLatestImage()
                    if (image != null) {
                        processJpegImage(image)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "获取JPEG图像失败", e)
                }
            }, backgroundHandler)
            
            // 打开相机（异步）
            sessionCreationResult = CompletableDeferred()
            cameraOpenCloseLock.acquire()
            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    cameraDevice = camera
                    Log.d(TAG, "相机已打开")
                    initializationResult?.complete(true)
                    createCaptureSession()
                }
                
                override fun onDisconnected(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                    Log.e(TAG, "相机已断开连接")
                    initializationResult?.complete(false)
                    sessionCreationResult?.complete(false)
                }
                
                override fun onError(camera: CameraDevice, error: Int) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                    Log.e(TAG, "相机打开失败: $error")
                    initializationResult?.complete(false)
                    sessionCreationResult?.complete(false)
                }
            }, backgroundHandler)
            
            // 等待相机打开（最多等待5秒）
            val cameraOpened = try {
                withTimeout(5000) {
                    initializationResult?.await() ?: false
                }
            } catch (e: TimeoutCancellationException) {
                Log.e(TAG, "等待相机打开超时")
                false
            }
            
            if (!cameraOpened) {
                initializationResult = null
                sessionCreationResult = null
                return false
            }
            
            // 等待session创建完成（最多等待3秒）
            val sessionCreated = try {
                withTimeout(3000) {
                    sessionCreationResult?.await() ?: false
                }
            } catch (e: TimeoutCancellationException) {
                Log.e(TAG, "等待session创建超时")
                false
            }
            
            initializationResult = null
            sessionCreationResult = null
            return sessionCreated
        } catch (e: SecurityException) {
            Log.e(TAG, "初始化相机失败：权限不足", e)
            initializationResult?.complete(false)
            sessionCreationResult?.complete(false)
            initializationResult = null
            sessionCreationResult = null
            return false
        } catch (e: CameraAccessException) {
            Log.e(TAG, "初始化相机失败：相机访问异常，错误代码: ${e.reason}", e)
            initializationResult?.complete(false)
            sessionCreationResult?.complete(false)
            initializationResult = null
            sessionCreationResult = null
            return false
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "初始化相机失败：参数错误 - ${e.message}", e)
            initializationResult?.complete(false)
            sessionCreationResult?.complete(false)
            initializationResult = null
            sessionCreationResult = null
            return false
        } catch (e: Exception) {
            Log.e(TAG, "初始化相机失败：未知异常 - ${e.javaClass.simpleName}: ${e.message}", e)
            e.printStackTrace()
            initializationResult?.complete(false)
            sessionCreationResult?.complete(false)
            initializationResult = null
            sessionCreationResult = null
            return false
        }
    }
    
    private fun createCaptureSession() {
        try {
            val camera = cameraDevice ?: return
            val imageReaderSurface = imageReader?.surface ?: return
            
            val surfaces = mutableListOf<Surface>(imageReaderSurface)
            
            // 录制时只使用预览和录制Surface，非录制时添加JPEG Surface用于拍照
            if (isRecording) {
                val surfaceToAdd = persistentSurface ?: mediaRecorder?.surface
                surfaceToAdd?.let { surfaces.add(it) }
            } else {
                jpegImageReader?.surface?.let { surfaces.add(it) }
            }
            
            Log.d(TAG, "创建捕获会话，surfaces数量: ${surfaces.size}")
            camera.createCaptureSession(
                surfaces,
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        Log.d(TAG, "捕获会话配置成功")
                        captureSession = session
                        startPreview()
                        
                        // 如果正在等待初始化session创建，通知完成
                        sessionCreationResult?.complete(true)
                        
                        // 如果正在等待录制会话配置，通知完成
                        recordingSessionResult?.complete(true)
                    }
                    
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "创建捕获会话失败")
                        // 如果正在等待初始化session创建，通知失败
                        sessionCreationResult?.complete(false)
                        
                        // 如果正在等待录制会话配置，通知失败
                        recordingSessionResult?.complete(false)
                    }
                    
                    override fun onClosed(session: CameraCaptureSession) {
                        super.onClosed(session)
                        Log.d(TAG, "捕获会话已关闭")
                        sessionCloseResult?.complete(Unit) // 通知session已关闭
                    }
                },
                backgroundHandler
            )
        } catch (e: Exception) {
            Log.e(TAG, "创建捕获会话异常", e)
            // 如果正在等待初始化session创建，通知失败
            sessionCreationResult?.complete(false)
            // 如果正在等待录制会话配置，通知失败
            recordingSessionResult?.complete(false)
        }
    }
    
    private fun startPreview() {
        try {
            val session = captureSession ?: return
            val camera = cameraDevice ?: return
            
            val requestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            imageReader?.surface?.let { requestBuilder.addTarget(it) }
            
            // 录制时添加MediaRecorder的Surface
            if (isRecording) {
                val surfaceToAdd = persistentSurface ?: mediaRecorder?.surface
                surfaceToAdd?.let { requestBuilder.addTarget(it) }
            }
            
            requestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            requestBuilder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            
            session.setRepeatingRequest(requestBuilder.build(), null, backgroundHandler)
            Log.d(TAG, "预览已启动")
        } catch (e: Exception) {
            Log.e(TAG, "启动预览失败", e)
        }
    }
    
    private fun stopPreview() {
        try {
            val session = captureSession ?: return
            session.stopRepeating()
            Log.d(TAG, "预览已停止")
        } catch (e: Exception) {
            Log.e(TAG, "停止预览失败", e)
        }
    }

    // 恢复预览（应用切回前台时调用）
    fun resumePreview() {
        try {
            if (cameraDevice == null || captureSession == null) {
                Log.w(TAG, "相机未初始化，无法恢复预览")
                return
            }
            Log.d(TAG, "恢复预览")
            startPreview()
        } catch (e: Exception) {
            Log.e(TAG, "恢复预览失败", e)
        }
    }
    
    private fun processPreviewImage(image: android.media.Image) {
        try {
            // 将YUV420_888转换为NV21格式，然后转换为JPEG
            val yPlane = image.planes[0]
            val uPlane = image.planes[1]
            val vPlane = image.planes[2]
            
            val yBuffer = yPlane.buffer
            val uBuffer = uPlane.buffer
            val vBuffer = vPlane.buffer
            
            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining()
            val vSize = vBuffer.remaining()
            
            var width = image.width
            var height = image.height
            
            // 创建NV21格式的字节数组
            val nv21 = ByteArray(ySize + uSize + vSize)
            
            yBuffer.get(nv21, 0, ySize)
            vBuffer.get(nv21, ySize, vSize)
            uBuffer.get(nv21, ySize + vSize, uSize)
            
            // 预览流：只发送原始YUV数据，不做旋转处理
            // 旋转由客户端根据锁定状态和方向统一处理
            val yuvImage = android.graphics.YuvImage(
                nv21,
                ImageFormat.NV21,
                width,
                height,
                null
            )
            
            val jpegOutputStream = java.io.ByteArrayOutputStream()
            yuvImage.compressToJpeg(
                android.graphics.Rect(0, 0, width, height),
                70, // JPEG质量
                jpegOutputStream
            )
            
            val jpegBytes = jpegOutputStream.toByteArray()
            jpegOutputStream.close()
            
            // 调用回调函数传递JPEG数据（原始数据，未旋转）
            previewFrameCallback?.invoke(jpegBytes)
        } catch (e: Exception) {
            Log.e(TAG, "处理预览图像失败", e)
        }
    }
    
    
    fun startRecording(
        outputPath: String, 
        videoQuality: String = "ultra", 
        enableAudio: Boolean = true,
        videoSize: Map<String, Int>? = null,
        videoFpsRange: Map<String, Int>? = null
    ): Boolean {
        try {
            if (isRecording) {
                Log.w(TAG, "已经在录制中")
                return false
            }
            
            // 检查相机设备是否有效
            val cameraIdStr = cameraDevice?.id
            if (cameraIdStr == null) {
                Log.e(TAG, "相机设备ID为空")
                return false
            }
            
            // 检查会话是否有效
            val existingSession = captureSession
            if (existingSession == null) {
                Log.e(TAG, "录制失败: captureSession为null")
                return false
            }
            
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            
            // 获取相机特性以确定录制尺寸
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            
            // 使用CamcorderProfile获取设备支持的配置
            val cameraId = cameraIdStr.toIntOrNull() ?: 0
            var profile: CamcorderProfile? = null
            var finalVideoSize = android.util.Size(1920, 1080)
            var videoBitRate = 8000000
            var videoFrameRate = 30
            var audioBitRate = 128000
            var audioSampleRate = 44100
            
            // 如果用户指定了分辨率，优先使用用户设置
            val userVideoSize = if (videoSize != null && videoSize.containsKey("width") && videoSize.containsKey("height")) {
                android.util.Size(videoSize["width"]!!, videoSize["height"]!!)
            } else {
                null
            }
            
            // 如果用户指定了帧率，优先使用用户设置
            val userVideoFrameRate = if (videoFpsRange != null && videoFpsRange.containsKey("max")) {
                videoFpsRange["max"]!!
            } else {
                null
            }
            
            // 根据videoQuality参数选择质量级别（仅在用户未指定分辨率时使用）
            val targetQualityLevel = when (videoQuality) {
                "ultra" -> CamcorderProfile.QUALITY_HIGH
                "high" -> CamcorderProfile.QUALITY_1080P
                "medium" -> CamcorderProfile.QUALITY_720P
                "low" -> CamcorderProfile.QUALITY_480P
                else -> CamcorderProfile.QUALITY_HIGH
            }
            
            // 按质量级别降级尝试（从目标质量开始）
            val qualityLevels = arrayOf(
                targetQualityLevel,
                CamcorderProfile.QUALITY_HIGH,
                CamcorderProfile.QUALITY_1080P,
                CamcorderProfile.QUALITY_720P,
                CamcorderProfile.QUALITY_480P,
                CamcorderProfile.QUALITY_LOW
            )
            
            // 先获取MediaRecorder支持的尺寸列表，用于验证用户指定的分辨率
            val characteristics = cameraManager.getCameraCharacteristics(cameraIdStr)
            val streamConfigurationMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val videoSizes = streamConfigurationMap?.getOutputSizes(MediaRecorder::class.java)
            
            for (quality in qualityLevels) {
                try {
                    if (CamcorderProfile.hasProfile(cameraId, quality)) {
                        profile = CamcorderProfile.get(cameraId, quality)
                        val profileVideoSize = android.util.Size(profile.videoFrameWidth, profile.videoFrameHeight)
                        
                        // 使用用户指定的分辨率（如果提供），否则使用profile的分辨率
                        // 注意：由于现在只显示CamcorderProfile支持的分辨率，用户指定的分辨率应该总是支持的
                        if (userVideoSize != null) {
                            finalVideoSize = userVideoSize
                            Log.d(TAG, "使用用户指定的分辨率: ${finalVideoSize.width}x${finalVideoSize.height}")
                        } else {
                            finalVideoSize = profileVideoSize
                            Log.d(TAG, "使用profile的分辨率: ${finalVideoSize.width}x${finalVideoSize.height}")
                        }
                        videoBitRate = profile.videoBitRate
                        // 只有在用户未指定帧率时才使用profile的帧率
                        if (userVideoFrameRate == null) {
                            videoFrameRate = profile.videoFrameRate
                        } else {
                            videoFrameRate = userVideoFrameRate
                        }
                        audioBitRate = profile.audioBitRate
                        audioSampleRate = profile.audioSampleRate
                        Log.d(TAG, "使用CamcorderProfile质量级别: $quality (请求: $videoQuality)")
                        Log.d(TAG, "最终录制参数: 尺寸: ${finalVideoSize.width}x${finalVideoSize.height}, 帧率: $videoFrameRate fps, 比特率: $videoBitRate")
                        if (userVideoFrameRate != null) {
                            Log.d(TAG, "使用用户指定的帧率: $userVideoFrameRate fps")
                        }
                        break
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "无法获取CamcorderProfile质量级别 $quality: ${e.message}")
                }
            }
            
            // CamcorderProfile不可用时，使用Camera2 API（理论上不应该发生，因为现在只显示CamcorderProfile支持的分辨率）
            if (profile == null) {
                Log.w(TAG, "警告：CamcorderProfile不可用，使用Camera2 API降级方案")
                // 如果用户指定了分辨率，使用它；否则使用MediaRecorder支持的第一个分辨率
                if (userVideoSize != null) {
                    finalVideoSize = userVideoSize
                    Log.d(TAG, "使用用户指定的分辨率: ${finalVideoSize.width}x${finalVideoSize.height}")
                } else {
                    finalVideoSize = videoSizes?.firstOrNull() ?: android.util.Size(1920, 1080)
                    Log.d(TAG, "使用Camera2 API获取的录制尺寸: ${finalVideoSize.width}x${finalVideoSize.height}")
                }
                
                if (userVideoFrameRate != null) {
                    videoFrameRate = userVideoFrameRate
                    Log.d(TAG, "使用用户指定的帧率: $videoFrameRate fps")
                } else {
                    videoFrameRate = 30 // 默认帧率
                }
            }
            
            currentVideoPath = outputPath
            recordingStartTime = System.currentTimeMillis()
            recordingSessionResult = CompletableDeferred()
            sessionCloseResult = CompletableDeferred()
            
            // 使用持久化Surface（Android API 23+）以提高兼容性
            var recorderSurface: Surface? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    // 创建持久化Surface
                    persistentSurface = MediaCodec.createPersistentInputSurface()
                    Log.d(TAG, "创建持久化Surface成功")
                } catch (e: Exception) {
                    Log.e(TAG, "创建持久化Surface失败，回退到普通Surface: ${e.message}")
                    persistentSurface = null
                }
            }
            
            // 创建MediaRecorder
            mediaRecorder = MediaRecorder().apply {
                // 设置音频源（必须在视频源之前，仅在启用音频时设置）
                if (enableAudio) {
                    setAudioSource(MediaRecorder.AudioSource.MIC)
                }
                // 设置视频源
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                // 设置输出格式
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                // 设置输出文件
                setOutputFile(outputPath)
                // 设置音频编码器（仅在启用音频时设置）
                if (enableAudio) {
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(audioBitRate)
                    setAudioSamplingRate(audioSampleRate)
                }
                // 设置视频编码器
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoSize(finalVideoSize.width, finalVideoSize.height)
                setVideoFrameRate(videoFrameRate)
                setVideoEncodingBitRate(videoBitRate)
                
                // 设置视频方向（与拍照方向计算逻辑一致，确保预览和拍摄方向一致）
                val videoOrientation = if (orientationLocked) {
                    // 方向锁定：使用手动旋转角度
                    // sensorOrientation + 90（基础补偿）+ lockedRotationAngle（手动旋转）
                    (sensorOrientation + 90 + lockedRotationAngle) % 360
                } else {
                    // 方向解锁：使用重力感应调整方向
                    // 计算视频方向：sensorOrientation + deviceOrientation
                    // deviceOrientation是相对于竖屏的角度（0, 90, 180, 270）
                    (sensorOrientation + currentDeviceOrientation) % 360
                }
                setOrientationHint(videoOrientation)
                Log.d(TAG, "MediaRecorder配置: 分辨率=${finalVideoSize.width}x${finalVideoSize.height}, 帧率=${videoFrameRate}fps, 比特率=${videoBitRate}, 方向=$videoOrientation (锁定=$orientationLocked, 传感器方向=$sensorOrientation, ${if (orientationLocked) "锁定角度=$lockedRotationAngle" else "设备方向=$currentDeviceOrientation"})")
                
                // 如果使用持久化Surface，设置它
                val persistentSurfaceToUse = persistentSurface
                if (persistentSurfaceToUse != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        setInputSurface(persistentSurfaceToUse)
                        recorderSurface = persistentSurfaceToUse
                        Log.d(TAG, "使用持久化Surface设置MediaRecorder")
                    } catch (e: Exception) {
                        Log.e(TAG, "设置持久化Surface失败，回退到普通Surface: ${e.message}")
                        persistentSurface = null
                    }
                }
                
                // 设置监听器为null
                setOnErrorListener(null)
                setOnInfoListener(null)
            }
            
            // 准备MediaRecorder
            try {
                mediaRecorder?.prepare()
                Log.d(TAG, "MediaRecorder.prepare()成功")
            } catch (e: Exception) {
                Log.e(TAG, "MediaRecorder.prepare()失败: ${e.javaClass.simpleName} - ${e.message}", e)
                isRecording = false
                mediaRecorder?.release()
                mediaRecorder = null
                persistentSurface?.release()
                persistentSurface = null
                currentVideoPath = null
                recordingSessionResult = null
                sessionCloseResult = null
                return false
            }
            
            // 如果没有使用持久化Surface，获取普通的Surface
            if (recorderSurface == null) {
                recorderSurface = mediaRecorder?.surface
            }
            
            // 验证Surface是否有效
            if (recorderSurface == null) {
                Log.e(TAG, "无法获取MediaRecorder的Surface")
                isRecording = false
                mediaRecorder?.release()
                mediaRecorder = null
                persistentSurface?.release()
                persistentSurface = null
                currentVideoPath = null
                recordingSessionResult = null
                sessionCloseResult = null
                return false
            }
            
            // 检查当前session是否有效且可以重用
            val existingSessionForReuse = captureSession
            val canReuseSession = existingSessionForReuse != null && cameraDevice != null
            
            if (canReuseSession) {
                // 如果session有效，尝试重用现有session
                // 先停止预览，然后添加MediaRecorder的Surface
                try {
                    stopPreview()
                } catch (e: Exception) {
                    Log.w(TAG, "停止预览时发生异常: ${e.message}")
                }
                
                // 使用现有session，直接启动MediaRecorder
                // MediaRecorder的Surface已经在createCaptureSession中添加了（如果isRecording为true）
                // 但我们需要重新创建session以包含MediaRecorder的Surface
                Log.d(TAG, "重用现有session，需要重新配置以添加MediaRecorder Surface")
            }
            
            // 设置录制标志（必须在创建session之前设置，因为createCaptureSession会检查isRecording）
            isRecording = true
            
            if (!canReuseSession) {
                // 如果没有有效session，创建新的
                Log.d(TAG, "创建新的captureSession用于录制")
                createCaptureSession()
                
                // 等待captureSession配置完成
                val sessionConfigured = kotlinx.coroutines.runBlocking {
                    try {
                        withTimeout(5000) {
                            recordingSessionResult?.await() ?: false
                        }
                    } catch (e: TimeoutCancellationException) {
                        Log.e(TAG, "等待captureSession配置超时")
                        false
                    }
                }
                
                if (!sessionConfigured) {
                    Log.e(TAG, "captureSession配置失败，无法启动录制")
                    // 注意：如果使用了真正支持的参数仍然失败，可能是设备硬件问题或代码bug
                    isRecording = false
                    mediaRecorder?.release()
                    mediaRecorder = null
                    persistentSurface?.release()
                    persistentSurface = null
                    currentVideoPath = null
                    recordingSessionResult = null
                    sessionCloseResult = null
                    return false
                }
            } else {
                // 如果有有效session，需要重新配置以添加MediaRecorder的Surface
                // 关闭旧session并创建新session
                try {
                    stopPreview()
                } catch (e: Exception) {
                    Log.w(TAG, "停止预览时发生异常（可能session已关闭）: ${e.message}")
                }
                
                // 关闭旧的captureSession，等待它完全关闭
                existingSessionForReuse?.close()
                
                // 等待旧的session完全关闭（最多2秒）
                val sessionClosed = kotlinx.coroutines.runBlocking {
                    try {
                        withTimeout(2000) {
                            sessionCloseResult?.await()
                            true
                        }
                    } catch (e: TimeoutCancellationException) {
                        Log.e(TAG, "等待旧的captureSession关闭超时")
                        false
                    }
                }
                
                if (!sessionClosed) {
                    Log.w(TAG, "旧的captureSession未能及时关闭，继续尝试创建新session")
                }
                
                // 创建新的captureSession，包含MediaRecorder的Surface
                createCaptureSession()
                
                // 等待captureSession配置完成
                val sessionConfigured = kotlinx.coroutines.runBlocking {
                    try {
                        withTimeout(5000) {
                            recordingSessionResult?.await() ?: false
                        }
                    } catch (e: TimeoutCancellationException) {
                        Log.e(TAG, "等待captureSession配置超时")
                        false
                    }
                }
                
                if (!sessionConfigured) {
                    Log.e(TAG, "captureSession配置失败，无法启动录制")
                    // 注意：如果使用了真正支持的参数仍然失败，可能是设备硬件问题或代码bug
                    isRecording = false
                    mediaRecorder?.release()
                    mediaRecorder = null
                    persistentSurface?.release()
                    persistentSurface = null
                    currentVideoPath = null
                    recordingSessionResult = null
                    sessionCloseResult = null
                    return false
                }
            }
            
            // captureSession配置成功后，启动MediaRecorder
            mediaRecorder?.start()
            
            Log.d(TAG, "开始录制: $outputPath, 尺寸: ${finalVideoSize.width}x${finalVideoSize.height}, 帧率: ${videoFrameRate}fps")
            recordingSessionResult = null
            sessionCloseResult = null
            return true
        } catch (e: Exception) {
            Log.e(TAG, "开始录制失败", e)
            isRecording = false
            mediaRecorder?.release()
            mediaRecorder = null
            persistentSurface?.release()
            persistentSurface = null
            currentVideoPath = null
            recordingSessionResult?.complete(false)
            recordingSessionResult = null
            sessionCloseResult = null
            return false
        }
    }
    
    fun stopRecording(): String? {
        // 先保存路径，避免在异常情况下丢失
        val path = currentVideoPath
        val recorder = mediaRecorder
        
        try {
            if (!isRecording) {
                Log.w(TAG, "未在录制中")
                return null
            }
            
            if (path == null) {
                Log.e(TAG, "停止录制失败: currentVideoPath为null")
                isRecording = false
                recorder?.release()
                mediaRecorder = null
                return null
            }
            
            if (recorder == null) {
                Log.e(TAG, "停止录制失败: mediaRecorder为null")
                isRecording = false
                currentVideoPath = null
                return null
            }
            
            // 确保录制时间至少1秒
            val recordingDuration = System.currentTimeMillis() - recordingStartTime
            if (recordingDuration < 1000) {
                Log.w(TAG, "录制时间过短: ${recordingDuration}ms，等待至少1秒")
                // 等待到至少1秒
                val waitTime = 1000 - recordingDuration
                Thread.sleep(waitTime)
            }
            
            // 移除监听器以避免异常
            try {
                recorder.setOnErrorListener(null)
                recorder.setOnInfoListener(null)
            } catch (e: Exception) {
                Log.w(TAG, "移除监听器失败（可能已释放）: $e")
            }
            
            // 先停止MediaRecorder，再关闭captureSession
            try {
                recorder.stop()
                Log.d(TAG, "MediaRecorder.stop()成功")
            } catch (e: IllegalStateException) {
                Log.e(TAG, "MediaRecorder.stop()失败: IllegalStateException - ${e.message}", e)
                throw e
            } catch (e: RuntimeException) {
                Log.e(TAG, "MediaRecorder.stop()失败: RuntimeException - ${e.message}", e)
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "MediaRecorder.stop()失败: ${e.javaClass.simpleName} - ${e.message}", e)
                throw e
            }
            
            // 释放MediaRecorder资源
            try {
                recorder.release()
                Log.d(TAG, "MediaRecorder.release()成功")
            } catch (e: Exception) {
                Log.e(TAG, "MediaRecorder.release()失败: $e", e)
            }
            
            mediaRecorder = null
            currentVideoPath = null
            isRecording = false
            
            // 释放持久化Surface
            persistentSurface?.release()
            persistentSurface = null
            
            // 重新创建捕获会话（移除MediaRecorder的Surface）
            captureSession?.close()
            createCaptureSession()
            
            Log.d(TAG, "停止录制成功: $path")
            return path
        } catch (e: Exception) {
            Log.e(TAG, "停止录制失败: ${e.javaClass.simpleName} - ${e.message}", e)
            isRecording = false
            
            // 确保释放MediaRecorder资源
            try {
                recorder?.release()
            } catch (releaseException: Exception) {
                Log.e(TAG, "释放MediaRecorder资源失败: $releaseException", releaseException)
            }
            mediaRecorder = null
            
            // 释放持久化Surface
            persistentSurface?.release()
            persistentSurface = null
            
            // 如果文件已创建，返回路径
            if (path != null) {
                val file = File(path)
                if (file.exists() && file.length() > 0) {
                    Log.w(TAG, "停止录制时发生异常，但文件已存在，返回路径: $path")
                    currentVideoPath = null
                    return path
                } else {
                    Log.e(TAG, "停止录制时发生异常，且文件不存在或为空: $path")
                }
            }
            return null
        }
    }
    
    suspend fun takePicture(outputPath: String): String? {
        try {
            val session = captureSession ?: run {
                Log.e(TAG, "拍照失败: captureSession为null")
                return null
            }
            
            // 注意：不能通过调用capture来检查会话状态，因为这会触发实际的拍照
            // 会话状态检查在调用capture之前通过检查session是否为null来完成
            // 如果session已关闭，会在后续的capture调用中抛出异常，我们会在那里处理
            
            val camera = cameraDevice ?: run {
                Log.e(TAG, "拍照失败: cameraDevice为null")
                return null
            }
            val jpegSurface = jpegImageReader?.surface ?: run {
                Log.e(TAG, "拍照失败: jpegImageReader或surface为null")
                return null
            }
            
            Log.d(TAG, "开始拍照，输出路径: $outputPath")
            pictureResult = CompletableDeferred()
            currentPicturePath = outputPath
            
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            
            val requestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            requestBuilder.addTarget(jpegSurface)
            
            // 保持预览流运行
            imageReader?.surface?.let { requestBuilder.addTarget(it) }
            
            requestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            requestBuilder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON_AUTO_FLASH)
            
            // 获取相机方向并设置JPEG方向
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val characteristics = cameraManager.getCameraCharacteristics(camera.id)
            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            
            val jpegOrientation = if (orientationLocked) {
                // 方向锁定：使用手动旋转角度
                // sensorOrientation + 90（基础补偿）+ lockedRotationAngle（手动旋转）
                (sensorOrientation + 90 + lockedRotationAngle) % 360
            } else {
                // 方向解锁：使用重力感应调整方向
                // 计算JPEG方向：sensorOrientation + deviceOrientation
                // deviceOrientation是相对于竖屏的角度（0, 90, 180, 270）
                (sensorOrientation + currentDeviceOrientation) % 360
            }
            
            Log.d(TAG, "拍照方向设置: 锁定=$orientationLocked, 传感器方向=$sensorOrientation, 设备方向=$currentDeviceOrientation, JPEG方向=$jpegOrientation")
            requestBuilder.set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation)
            
            // 触发拍照
            Log.d(TAG, "发送拍照请求...")
            try {
                session.capture(requestBuilder.build(), object : CaptureCallback() {
                    override fun onCaptureCompleted(
                        session: CameraCaptureSession,
                        request: CaptureRequest,
                        result: TotalCaptureResult
                    ) {
                        Log.d(TAG, "拍照请求完成，等待JPEG图像...")
                    }
                    
                    override fun onCaptureFailed(
                        session: CameraCaptureSession,
                        request: CaptureRequest,
                        failure: CaptureFailure
                    ) {
                        Log.e(TAG, "拍照请求失败: reason=${failure.reason}, wasImageCaptured=${failure.wasImageCaptured()}")
                        pictureResult?.complete(null)
                        pictureResult = null
                        currentPicturePath = null
                    }
                }, backgroundHandler)
            } catch (e: IllegalStateException) {
                if (e.message?.contains("closed") == true) {
                    Log.e(TAG, "拍照失败: captureSession已关闭")
                    pictureResult?.complete(null)
                    pictureResult = null
                    currentPicturePath = null
                    return null
                }
                throw e
            }
            
            // 等待JPEG图像处理完成
            Log.d(TAG, "等待JPEG图像处理完成...")
            val result = try {
                withTimeout(5000L) {
                    pictureResult?.await() ?: null
                }
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                Log.e(TAG, "等待JPEG图像超时（5秒）")
                pictureResult?.complete(null)
                null
            }
            pictureResult = null
            currentPicturePath = null
            Log.d(TAG, "拍照结果: ${if (result != null) "成功: $result" else "失败: null"}")
            return result
        } catch (e: Exception) {
            Log.e(TAG, "拍照异常", e)
            pictureResult?.complete(null)
            pictureResult = null
            currentPicturePath = null
            return null
        }
    }
    
    private fun processJpegImage(image: android.media.Image) {
        try {
            Log.d(TAG, "收到JPEG图像，开始处理...")
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            
            // 使用currentPicturePath保存文件
            val outputPath = currentPicturePath
            if (outputPath != null) {
                val file = File(outputPath)
                file.writeBytes(bytes)
                
                Log.d(TAG, "JPEG图像已保存: $outputPath, 大小: ${bytes.size} 字节")
                
                pictureResult?.complete(outputPath)
                pictureResult = null
            } else {
                Log.e(TAG, "当前拍照路径为null，无法保存JPEG图像")
                pictureResult?.complete(null)
                pictureResult = null
            }
        } catch (e: Exception) {
            Log.e(TAG, "处理JPEG图像失败", e)
            pictureResult?.complete(null)
            pictureResult = null
        } finally {
            image.close()
        }
    }
    
    private var currentPicturePath: String? = null
    
    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("CameraBackground").also { it.start() }
        backgroundHandler = Handler(backgroundThread?.looper!!)
    }
    
    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            Log.e(TAG, "停止后台线程失败", e)
        }
    }
    
    fun release() {
        try {
            cameraOpenCloseLock.acquire()
            
            captureSession?.close()
            captureSession = null
            
            mediaRecorder?.apply {
                if (isRecording) {
                    stop()
                }
                release()
            }
            mediaRecorder = null
            
            cameraDevice?.close()
            cameraDevice = null
            
            imageReader?.close()
            imageReader = null
            
            stopBackgroundThread()
            
            cameraOpenCloseLock.release()
            
            Log.d(TAG, "相机资源已释放")
        } catch (e: Exception) {
            Log.e(TAG, "释放相机资源失败", e)
        }
    }
    
    // 获取相机能力信息（不需要初始化相机）
    fun getCameraCapabilities(cameraId: String): Map<String, Any>? {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val streamConfigurationMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            
            // 获取支持的输出尺寸
            val jpegSizes = streamConfigurationMap?.getOutputSizes(ImageFormat.JPEG)?.map { 
                mapOf("width" to it.width, "height" to it.height)
            } ?: emptyList()
            
            val previewSizes = streamConfigurationMap?.getOutputSizes(ImageFormat.YUV_420_888)?.map {
                mapOf("width" to it.width, "height" to it.height)
            } ?: emptyList()
            
            // 获取支持的CamcorderProfile质量级别，并收集真正支持的视频分辨率
            val supportedVideoQualities = mutableListOf<String>()
            val cameraIdInt = cameraId.toIntOrNull() ?: 0
            val videoSizesSet = mutableSetOf<Pair<Int, Int>>() // 使用Set去重
            val resolutionFpsMap = mutableMapOf<Pair<Int, Int>, MutableSet<Int>>() // 记录每个分辨率对应的帧率
            
            val qualityLevels = mapOf(
                "ultra" to CamcorderProfile.QUALITY_HIGH,
                "high" to CamcorderProfile.QUALITY_1080P,
                "medium" to CamcorderProfile.QUALITY_720P,
                "low" to CamcorderProfile.QUALITY_480P
            )
            
            // 遍历所有可能的CamcorderProfile质量级别
            val allQualityLevels = listOf(
                CamcorderProfile.QUALITY_2160P,
                CamcorderProfile.QUALITY_1080P,
                CamcorderProfile.QUALITY_720P,
                CamcorderProfile.QUALITY_480P,
                CamcorderProfile.QUALITY_QVGA,
                CamcorderProfile.QUALITY_CIF,
                CamcorderProfile.QUALITY_QCIF,
                CamcorderProfile.QUALITY_HIGH,
                CamcorderProfile.QUALITY_LOW,
                CamcorderProfile.QUALITY_TIME_LAPSE_2160P,
                CamcorderProfile.QUALITY_TIME_LAPSE_1080P,
                CamcorderProfile.QUALITY_TIME_LAPSE_720P,
                CamcorderProfile.QUALITY_TIME_LAPSE_480P,
                CamcorderProfile.QUALITY_TIME_LAPSE_QVGA,
                CamcorderProfile.QUALITY_TIME_LAPSE_CIF,
                CamcorderProfile.QUALITY_TIME_LAPSE_QCIF,
                CamcorderProfile.QUALITY_TIME_LAPSE_HIGH,
                CamcorderProfile.QUALITY_TIME_LAPSE_LOW
            )
            
            // 收集所有CamcorderProfile支持的分辨率和对应的帧率（这些是设备保证支持的）
            for (qualityLevel in allQualityLevels) {
                try {
                    if (CamcorderProfile.hasProfile(cameraIdInt, qualityLevel)) {
                        val profile = CamcorderProfile.get(cameraIdInt, qualityLevel)
                        val resolution = Pair(profile.videoFrameWidth, profile.videoFrameHeight)
                        videoSizesSet.add(resolution)
                        // 记录该分辨率对应的帧率
                        if (!resolutionFpsMap.containsKey(resolution)) {
                            resolutionFpsMap[resolution] = mutableSetOf()
                        }
                        resolutionFpsMap[resolution]?.add(profile.videoFrameRate)
                    }
                } catch (e: Exception) {
                    // 忽略不支持的profile
                }
            }
            
            // 检查标准质量级别
            for ((qualityName, qualityLevel) in qualityLevels) {
                try {
                    if (CamcorderProfile.hasProfile(cameraIdInt, qualityLevel)) {
                        val profile = CamcorderProfile.get(cameraIdInt, qualityLevel)
                        supportedVideoQualities.add(qualityName)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "无法检查质量级别 $qualityName: ${e.message}")
                }
            }
            
            // 将Set转换为List，并添加每个分辨率对应的帧率信息
            val videoSizes = videoSizesSet.map { resolution ->
                val supportedFps = resolutionFpsMap[resolution]?.sorted() ?: emptyList()
                mapOf(
                    "width" to resolution.first,
                    "height" to resolution.second,
                    "supportedFps" to supportedFps // 添加该分辨率支持的帧率列表
                )
            }
            
            Log.d(TAG, "CamcorderProfile支持的视频分辨率数量: ${videoSizes.size}")
            if (videoSizes.isEmpty()) {
                Log.w(TAG, "警告：未找到任何CamcorderProfile支持的分辨率，设备可能不支持视频录制")
            }
            
            // 检查是否有参数互相掣肘的情况
            val conflicts = mutableListOf<String>()
            for ((resolution, fpsSet) in resolutionFpsMap) {
                if (fpsSet.size > 1) {
                    // 同一分辨率支持多个帧率，这是正常的
                } else if (fpsSet.isEmpty()) {
                    conflicts.add("分辨率 ${resolution.first}x${resolution.second} 没有对应的帧率信息")
                }
            }
            
            // 检查是否有分辨率在CamcorderProfile中支持，但在CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES中不支持对应帧率
            val availableFpsRanges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES) ?: emptyArray()
            val availableFpsSet = mutableSetOf<Int>()
            for (fpsRange in availableFpsRanges) {
                availableFpsSet.add(fpsRange.lower)
                availableFpsSet.add(fpsRange.upper)
            }
            
            for ((resolution, fpsSet) in resolutionFpsMap) {
                for (fps in fpsSet) {
                    if (!availableFpsSet.contains(fps)) {
                        conflicts.add("分辨率 ${resolution.first}x${resolution.second} 在CamcorderProfile中支持 ${fps}fps，但在CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES中不支持")
                    }
                }
            }
            
            if (conflicts.isNotEmpty()) {
                Log.w(TAG, "检测到参数冲突：")
                for (conflict in conflicts) {
                    Log.w(TAG, "  - $conflict")
                }
            }
            
            // 获取传感器方向
            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            
            // 获取支持的AF模式
            val afModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.toList() ?: emptyList()
            
            // 获取支持的AE模式
            val aeModes = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_MODES)?.toList() ?: emptyList()
            
            // 获取支持的AWB模式
            val awbModes = characteristics.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)?.toList() ?: emptyList()
            
            // 获取支持的帧率范围
            val fpsRanges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.map {
                mapOf("min" to it.lower, "max" to it.upper)
            } ?: emptyList()
            
            // 获取镜头方向
            val lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING)
            val lensDirection = when (lensFacing) {
                CameraCharacteristics.LENS_FACING_BACK -> "back"
                CameraCharacteristics.LENS_FACING_FRONT -> "front"
                else -> "unknown"
            }
            
            // 收集CamcorderProfile支持的所有帧率（用于过滤fpsRanges）
            val supportedFpsSet = mutableSetOf<Int>()
            for (fpsSet in resolutionFpsMap.values) {
                supportedFpsSet.addAll(fpsSet)
            }
            
            // 只返回与CamcorderProfile兼容的帧率范围
            val compatibleFpsRanges = fpsRanges.filter { fpsRange ->
                val min = fpsRange["min"] as? Int ?: 0
                val max = fpsRange["max"] as? Int ?: 0
                // 如果帧率范围内有任何值在supportedFpsSet中，则认为兼容
                (min..max).any { it in supportedFpsSet }
            }
            
            return mapOf(
                "cameraId" to cameraId,
                "lensDirection" to lensDirection,
                "sensorOrientation" to sensorOrientation,
                "photoSizes" to jpegSizes,
                "previewSizes" to previewSizes,
                "videoSizes" to videoSizes, // 现在包含supportedFps字段
                "supportedVideoQualities" to supportedVideoQualities,
                "afModes" to afModes,
                "aeModes" to aeModes,
                "awbModes" to awbModes,
                "fpsRanges" to compatibleFpsRanges, // 只返回兼容的帧率范围
                "parameterConflicts" to conflicts // 添加参数冲突信息
            )
        } catch (e: Exception) {
            Log.e(TAG, "获取相机能力信息失败", e)
            return null
        }
    }
    
    // 获取所有可用相机的能力信息
    fun getAllCameraCapabilities(): List<Map<String, Any>> {
        val capabilities = mutableListOf<Map<String, Any>>()
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIds = cameraManager.cameraIdList
            
            for (cameraId in cameraIds) {
                val caps = getCameraCapabilities(cameraId)
                if (caps != null) {
                    capabilities.add(caps)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "获取所有相机能力信息失败", e)
        }
        return capabilities
    }
    
    // 设置方向锁定状态
    fun setOrientationLock(locked: Boolean) {
        orientationLocked = locked
        Log.d(TAG, "方向锁定状态已设置: $locked")
    }
    
    // 更新当前设备方向（用于解锁时计算方向）
    fun updateDeviceOrientation(orientation: Int) {
        currentDeviceOrientation = orientation
        Log.d(TAG, "设备方向已更新: $orientation 度")
    }
    
    // 设置锁定状态下的旋转角度
    fun setLockedRotationAngle(angle: Int) {
        lockedRotationAngle = angle
        Log.d(TAG, "锁定旋转角度已设置: $angle 度")
    }
    
    // 获取实际预览尺寸
    fun getPreviewSize(): Pair<Int, Int> {
        return Pair(actualPreviewWidth, actualPreviewHeight)
    }
    
    // 获取方向状态
    fun getOrientationStatus(): Map<String, Any> {
        return mapOf(
            "orientationLocked" to orientationLocked,
            "lockedRotationAngle" to lockedRotationAngle,
            "currentDeviceOrientation" to currentDeviceOrientation,
            "sensorOrientation" to sensorOrientation
        )
    }
}

