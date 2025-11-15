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
    
    // 拍照相关
    private var jpegImageReader: ImageReader? = null
    private var pictureResult: CompletableDeferred<String?>? = null
    
    // 预览帧回调
    var previewFrameCallback: ((ByteArray) -> Unit)? = null
    
    // 持久化Surface（用于兼容性）
    private var persistentSurface: Surface? = null
    
    suspend fun initialize(cameraId: String, previewWidth: Int, previewHeight: Int): Boolean {
        try {
            Log.d(TAG, "开始初始化相机，相机ID: $cameraId, 预览尺寸: ${previewWidth}x${previewHeight}")
            initializationResult = CompletableDeferred()
            
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            Log.d(TAG, "获取相机管理器成功")
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            Log.d(TAG, "获取相机特性成功")
            
            // 获取支持的输出尺寸
            val streamConfigurationMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val previewSizes = streamConfigurationMap?.getOutputSizes(ImageFormat.YUV_420_888)
            
            // 选择预览尺寸
            val previewSize = previewSizes?.firstOrNull { 
                it.width <= previewWidth && it.height <= previewHeight 
            } ?: previewSizes?.firstOrNull()
            
            if (previewSize == null) {
                Log.e(TAG, "无法找到合适的预览尺寸")
                initializationResult?.complete(false)
                return false
            }
            
            Log.d(TAG, "选择预览尺寸: ${previewSize.width}x${previewSize.height}")
            
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
            cameraOpenCloseLock.acquire()
            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    cameraDevice = camera
                    Log.d(TAG, "相机已打开")
                    createCaptureSession()
                    initializationResult?.complete(true)
                }
                
                override fun onDisconnected(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                    Log.e(TAG, "相机已断开连接")
                    initializationResult?.complete(false)
                }
                
                override fun onError(camera: CameraDevice, error: Int) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                    Log.e(TAG, "相机打开失败: $error")
                    initializationResult?.complete(false)
                }
            }, backgroundHandler)
            
            // 等待相机打开（最多等待5秒）
            val result = initializationResult?.await() ?: false
            initializationResult = null
            return result
        } catch (e: SecurityException) {
            Log.e(TAG, "初始化相机失败：权限不足", e)
            initializationResult?.complete(false)
            initializationResult = null
            return false
        } catch (e: CameraAccessException) {
            Log.e(TAG, "初始化相机失败：相机访问异常，错误代码: ${e.reason}", e)
            initializationResult?.complete(false)
            initializationResult = null
            return false
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "初始化相机失败：参数错误 - ${e.message}", e)
            initializationResult?.complete(false)
            initializationResult = null
            return false
        } catch (e: Exception) {
            Log.e(TAG, "初始化相机失败：未知异常 - ${e.javaClass.simpleName}: ${e.message}", e)
            e.printStackTrace()
            initializationResult?.complete(false)
            initializationResult = null
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
                        
                        // 如果正在等待录制会话配置，通知完成
                        recordingSessionResult?.complete(true)
                    }
                    
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "创建捕获会话失败")
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
            
            val width = image.width
            val height = image.height
            
            // 创建NV21格式的字节数组
            val nv21 = ByteArray(ySize + uSize + vSize)
            
            yBuffer.get(nv21, 0, ySize)
            vBuffer.get(nv21, ySize, vSize)
            uBuffer.get(nv21, ySize + vSize, uSize)
            
            // 使用YuvImage将NV21转换为JPEG
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
            
            // 调用回调函数传递JPEG数据
            previewFrameCallback?.invoke(jpegBytes)
        } catch (e: Exception) {
            Log.e(TAG, "处理预览图像失败", e)
        }
    }
    
    fun startRecording(outputPath: String): Boolean {
        try {
            if (isRecording) {
                Log.w(TAG, "已经在录制中")
                return false
            }
            
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            
            // 获取相机特性以确定录制尺寸
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIdStr = cameraDevice?.id
            if (cameraIdStr == null) {
                Log.e(TAG, "相机设备ID为空")
                return false
            }
            
            // 使用CamcorderProfile获取设备支持的配置
            val cameraId = cameraIdStr.toIntOrNull() ?: 0
            var profile: CamcorderProfile? = null
            var videoSize = android.util.Size(1920, 1080)
            var videoBitRate = 8000000
            var videoFrameRate = 30
            var audioBitRate = 128000
            var audioSampleRate = 44100
            
            // 按质量级别降级尝试
            val qualityLevels = arrayOf(
                CamcorderProfile.QUALITY_HIGH,
                CamcorderProfile.QUALITY_1080P,
                CamcorderProfile.QUALITY_720P,
                CamcorderProfile.QUALITY_480P,
                CamcorderProfile.QUALITY_LOW
            )
            
            for (quality in qualityLevels) {
                try {
                    if (CamcorderProfile.hasProfile(cameraId, quality)) {
                        profile = CamcorderProfile.get(cameraId, quality)
                        videoSize = android.util.Size(profile.videoFrameWidth, profile.videoFrameHeight)
                        videoBitRate = profile.videoBitRate
                        videoFrameRate = profile.videoFrameRate
                        audioBitRate = profile.audioBitRate
                        audioSampleRate = profile.audioSampleRate
                        Log.d(TAG, "使用CamcorderProfile质量级别: $quality, 尺寸: ${videoSize.width}x${videoSize.height}")
                        break
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "无法获取CamcorderProfile质量级别 $quality: ${e.message}")
                }
            }
            
            // CamcorderProfile不可用时，使用Camera2 API
            if (profile == null) {
                val characteristics = cameraManager.getCameraCharacteristics(cameraIdStr)
                val streamConfigurationMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val videoSizes = streamConfigurationMap?.getOutputSizes(MediaRecorder::class.java)
                videoSize = videoSizes?.firstOrNull() ?: android.util.Size(1920, 1080)
                Log.d(TAG, "使用Camera2 API获取的录制尺寸: ${videoSize.width}x${videoSize.height}")
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
                // 设置音频源（必须在视频源之前）
                setAudioSource(MediaRecorder.AudioSource.MIC)
                // 设置视频源
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                // 设置输出格式
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                // 设置输出文件
                setOutputFile(outputPath)
                // 设置音频编码器
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(audioBitRate)
                setAudioSamplingRate(audioSampleRate)
                // 设置视频编码器
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoSize(videoSize.width, videoSize.height)
                setVideoFrameRate(videoFrameRate)
                setVideoEncodingBitRate(videoBitRate)
                
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
            
            // 设置录制标志
            isRecording = true
            
            // 在关闭旧的captureSession之前，先停止预览请求
            try {
                stopPreview()
            } catch (e: Exception) {
                Log.w(TAG, "停止预览时发生异常（可能session已关闭）: ${e.message}")
            }
            
            // 现在关闭旧的captureSession，等待它完全关闭（通过回调）
            captureSession?.close()
            
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
            
            // captureSession配置成功后，启动MediaRecorder
            mediaRecorder?.start()
            
            Log.d(TAG, "开始录制: $outputPath, 尺寸: ${videoSize.width}x${videoSize.height}")
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
            val jpegOrientation = (sensorOrientation + 90) % 360
            requestBuilder.set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation)
            
            // 触发拍照
            Log.d(TAG, "发送拍照请求...")
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
}

