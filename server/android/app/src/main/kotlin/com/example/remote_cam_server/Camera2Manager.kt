package com.example.remote_cam_server

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.hardware.camera2.CameraCaptureSession.CaptureCallback
import android.media.ImageReader
import android.media.MediaRecorder
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
    
    private val cameraOpenCloseLock = Semaphore(1)
    private var initializationResult: CompletableDeferred<Boolean>? = null
    
    // 拍照相关
    private var jpegImageReader: ImageReader? = null
    private var pictureResult: CompletableDeferred<String?>? = null
    
    // 预览帧回调
    var previewFrameCallback: ((ByteArray) -> Unit)? = null
    
    suspend fun initialize(cameraId: String, previewWidth: Int, previewHeight: Int): Boolean {
        try {
            initializationResult = CompletableDeferred()
            
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            
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
            
            startBackgroundThread()
            
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
        } catch (e: Exception) {
            Log.e(TAG, "初始化相机失败", e)
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
            
            // 添加JPEG ImageReader的Surface（用于拍照）
            jpegImageReader?.surface?.let { surfaces.add(it) }
            
            // 如果正在录制，添加MediaRecorder的Surface
            if (isRecording && mediaRecorder != null) {
                mediaRecorder?.surface?.let { surfaces.add(it) }
            }
            
            Log.d(TAG, "创建捕获会话，surfaces数量: ${surfaces.size}")
            camera.createCaptureSession(
                surfaces,
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        startPreview()
                    }
                    
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "创建捕获会话失败")
                    }
                },
                backgroundHandler
            )
        } catch (e: Exception) {
            Log.e(TAG, "创建捕获会话异常", e)
        }
    }
    
    private fun startPreview() {
        try {
            val session = captureSession ?: return
            val camera = cameraDevice ?: return
            
            val requestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            imageReader?.surface?.let { requestBuilder.addTarget(it) }
            
            // 如果正在录制，添加MediaRecorder的Surface
            if (isRecording && mediaRecorder != null) {
                mediaRecorder?.surface?.let { requestBuilder.addTarget(it) }
            }
            
            requestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            requestBuilder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            
            session.setRepeatingRequest(requestBuilder.build(), null, backgroundHandler)
        } catch (e: Exception) {
            Log.e(TAG, "启动预览失败", e)
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
            val characteristics = cameraManager.getCameraCharacteristics(cameraIdStr)
            val streamConfigurationMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val videoSizes = streamConfigurationMap?.getOutputSizes(MediaRecorder::class.java)
            val videoSize = videoSizes?.firstOrNull() ?: android.util.Size(1920, 1080)
            
            mediaRecorder = MediaRecorder().apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setOutputFile(outputPath)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoSize(videoSize.width, videoSize.height)
                setVideoFrameRate(30)
                setVideoEncodingBitRate(8000000)
                
                prepare()
            }
            
            currentVideoPath = outputPath
            isRecording = true
            
            // 重新创建捕获会话以包含MediaRecorder的Surface
            captureSession?.close()
            createCaptureSession()
            
            mediaRecorder?.start()
            
            Log.d(TAG, "开始录制: $outputPath, 尺寸: ${videoSize.width}x${videoSize.height}")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "开始录制失败", e)
            isRecording = false
            mediaRecorder?.release()
            mediaRecorder = null
            return false
        }
    }
    
    fun stopRecording(): String? {
        try {
            if (!isRecording) {
                Log.w(TAG, "未在录制中")
                return null
            }
            
            mediaRecorder?.apply {
                stop()
                release()
            }
            mediaRecorder = null
            
            val path = currentVideoPath
            currentVideoPath = null
            isRecording = false
            
            // 重新创建捕获会话（移除MediaRecorder的Surface）
            captureSession?.close()
            createCaptureSession()
            
            Log.d(TAG, "停止录制: $path")
            return path
        } catch (e: Exception) {
            Log.e(TAG, "停止录制失败", e)
            isRecording = false
            mediaRecorder?.release()
            mediaRecorder = null
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
            
            // 等待JPEG图像处理完成（最多等待5秒）
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

