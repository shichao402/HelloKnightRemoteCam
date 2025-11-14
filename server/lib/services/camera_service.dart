import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import '../models/camera_status.dart';
import '../models/camera_settings.dart';
import '../models/file_info.dart';
import 'logger_service.dart';
import 'file_index_service.dart';
import 'media_scanner_service.dart';

class CameraService {
  CameraController? controller;
  CameraStatus status = CameraStatus.idle;
  CameraSettings settings = const CameraSettings();
  final LoggerService _logger = LoggerService();
  final FileIndexService _fileIndex = FileIndexService();
  
  bool _isRecording = false;
  bool _isTakingPhoto = false;
  String? _currentVideoPath;
  Uint8List? _lastPreviewFrame;
  
  // 预览流相关
  bool _isImageStreamActive = false;
  
  // 互斥锁，确保同一时间只有一个操作调用 takePicture()
  Future<void>? _takePictureLock;
  
  // 初始化文件索引服务
  Future<void> initializeFileIndex() async {
    await _fileIndex.initialize();
  }

  bool get isRecording => _isRecording;
  bool get isInitialized => controller?.value.isInitialized ?? false;
  Uint8List? get lastPreviewFrame => _lastPreviewFrame;

  // 初始化相机
  Future<void> initialize(CameraDescription camera, [CameraSettings? initialSettings]) async {
    if (initialSettings != null) {
      settings = initialSettings;
    }

    controller = CameraController(
      camera,
      settings.videoResolutionPreset,
      enableAudio: settings.enableAudio,
    );
    
    await controller!.initialize();
    
    // 启动预览流以获取预览帧（不触发闪光灯）
    _startImageStream();
    
    status = CameraStatus.idle;
  }
  
  // 启动图像流用于预览
  Future<void> _startImageStream() async {
    if (controller == null || !controller!.value.isInitialized) {
      _logger.log('无法启动预览流：相机未初始化', tag: 'PREVIEW');
      return;
    }
    
    if (_isImageStreamActive) {
      _logger.log('预览流已在运行', tag: 'PREVIEW');
      return;
    }
    
    try {
      _isImageStreamActive = true;
      await controller!.startImageStream((CameraImage image) {
        try {
          // 将 CameraImage 转换为 JPEG 字节
          // 使用 try-catch 包裹，避免回调中的错误导致崩溃
          _processCameraImage(image);
        } catch (e, stackTrace) {
          _logger.logError('图像流回调错误', error: e, stackTrace: stackTrace);
        }
      });
      _logger.logCamera('预览流已启动');
    } catch (e, stackTrace) {
      _logger.logError('启动预览流失败', error: e, stackTrace: stackTrace);
      _isImageStreamActive = false;
    }
  }
  
  // 停止图像流
  Future<void> _stopImageStream() async {
    if (!_isImageStreamActive || controller == null) {
      return;
    }
    
    try {
      await controller!.stopImageStream();
      _isImageStreamActive = false;
      _logger.logCamera('预览流已停止');
    } catch (e) {
      _logger.logError('停止预览流失败', error: e);
      _isImageStreamActive = false;
    }
  }
  
  // 处理相机图像，转换为 JPEG
  // 使用异步处理，避免阻塞图像流回调
  void _processCameraImage(CameraImage cameraImage) {
    // 异步处理，不阻塞图像流回调
    Future.microtask(() async {
      try {
        // 将 CameraImage (YUV420) 转换为 RGB Image
        final img.Image? rgbImage = _convertYUV420ToImage(cameraImage);
        if (rgbImage == null) {
          return;
        }
        
        // 编码为 JPEG
        final jpegBytes = img.encodeJpg(rgbImage, quality: settings.previewQuality);
        _lastPreviewFrame = Uint8List.fromList(jpegBytes);
      } catch (e, stackTrace) {
        _logger.logError('处理预览帧失败', error: e, stackTrace: stackTrace);
      }
    });
  }
  
  // 将 YUV420 格式的 CameraImage 转换为 RGB Image
  img.Image? _convertYUV420ToImage(CameraImage cameraImage) {
    try {
      if (cameraImage.planes.length < 3) {
        _logger.log('图像平面数不足: ${cameraImage.planes.length}', tag: 'PREVIEW');
        return null;
      }
      
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];
      
      final width = cameraImage.width;
      final height = cameraImage.height;
      
      // 检查图像尺寸是否合理
      if (width <= 0 || height <= 0 || width > 10000 || height > 10000) {
        _logger.log('无效的图像尺寸: $width x $height', tag: 'PREVIEW');
        return null;
      }
      
      // 检查字节数组边界
      final ySize = yPlane.bytes.length;
      final uSize = uPlane.bytes.length;
      final vSize = vPlane.bytes.length;
      
      if (ySize == 0 || uSize == 0 || vSize == 0) {
        _logger.log('图像数据为空', tag: 'PREVIEW');
        return null;
      }
      
      // 创建 RGB 图像
      final rgbImage = img.Image(width: width, height: height);
      
      // YUV420 到 RGB 转换（添加边界检查）
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          try {
            final yIndex = y * yPlane.bytesPerRow + x;
            final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);
            
            // 边界检查
            if (yIndex >= ySize || uvIndex >= uSize || uvIndex >= vSize) {
              continue;
            }
            
            final yValue = yPlane.bytes[yIndex];
            final uValue = uPlane.bytes[uvIndex];
            final vValue = vPlane.bytes[uvIndex];
            
            // YUV 到 RGB 转换
            final r = _yuvToR(yValue, uValue, vValue);
            final g = _yuvToG(yValue, uValue, vValue);
            final b = _yuvToB(yValue, uValue, vValue);
            
            rgbImage.setPixel(x, y, img.ColorRgb8(r, g, b));
          } catch (e) {
            // 单个像素转换失败，继续处理下一个
            continue;
          }
        }
      }
      
      return rgbImage;
    } catch (e, stackTrace) {
      _logger.logError('YUV420转换失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }
  
  // YUV 到 RGB 转换辅助函数
  int _yuvToR(int y, int u, int v) {
    final r = (y + 1.402 * (v - 128)).round().clamp(0, 255);
    return r;
  }
  
  int _yuvToG(int y, int u, int v) {
    final g = (y - 0.344 * (u - 128) - 0.714 * (v - 128)).round().clamp(0, 255);
    return g;
  }
  
  int _yuvToB(int y, int u, int v) {
    final b = (y + 1.772 * (u - 128)).round().clamp(0, 255);
    return b;
  }

  // 重新配置相机（用于更改设置）
  Future<void> reconfigure(CameraSettings newSettings, CameraDescription camera) async {
    if (status == CameraStatus.recording) {
      throw Exception('录像中无法更改设置');
    }

    status = CameraStatus.reconfiguring;
    settings = newSettings;

    // 停止预览流
    await _stopImageStream();
    
    // 释放旧的控制器
    await controller?.dispose();

    // 创建新的控制器
    controller = CameraController(
      camera,
      settings.videoResolutionPreset,
      enableAudio: settings.enableAudio,
    );
    
    await controller!.initialize();
    
    // 启动预览流
    _startImageStream();
    
    status = CameraStatus.idle;
  }

  // 拍照
  Future<String> takePicture() async {
    if (controller == null) {
      _logger.logError('拍照失败', error: Exception('相机控制器为null'));
      throw Exception('相机未初始化');
    }

    // 检查相机状态
    if (!controller!.value.isInitialized) {
      _logger.logError('拍照失败', error: Exception('相机未初始化'));
      throw Exception('相机未初始化');
    }

    // 检查是否有错误
    if (controller!.value.hasError) {
      final error = controller!.value.errorDescription ?? '未知错误';
      _logger.logError('拍照失败', error: Exception('相机错误: $error'));
      throw Exception('相机错误: $error');
    }

    _logger.logCamera('开始拍照', details: '相机状态: isInitialized=${controller!.value.isInitialized}, hasError=${controller!.value.hasError}');

    // 等待之前的操作完成
    if (_takePictureLock != null) {
      _logger.logCamera('等待之前的操作完成');
      await _takePictureLock;
    }

    // 创建新的锁
    final completer = Completer<void>();
    _takePictureLock = completer.future;

    try {
      status = CameraStatus.takingPhoto;
      _isTakingPhoto = true;

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'IMG_$timestamp.jpg';

      _logger.logCamera('调用takePicture', details: '文件名: $fileName');
      
      // 再次检查相机状态（可能在等待期间状态改变）
      if (!controller!.value.isInitialized || controller!.value.hasError) {
        throw Exception('相机状态异常: isInitialized=${controller!.value.isInitialized}, hasError=${controller!.value.hasError}');
      }

      final XFile image = await controller!.takePicture();
      _logger.logCamera('拍照成功', details: '临时文件: ${image.path}');
      
      // 保存到公共存储目录（Pictures/RemoteCam）
      // 从应用目录获取外部存储根目录
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('无法获取外部存储目录');
      }
      
      // 从 /storage/emulated/0/Android/data/.../files 回到 /storage/emulated/0
      final String storageRoot = externalDir.path.split('/Android/data')[0];
      final String publicPicturesPath = path.join(storageRoot, 'Pictures', 'RemoteCam');
      await Directory(publicPicturesPath).create(recursive: true);
      final String savedPath = path.join(publicPicturesPath, fileName);
      
      _logger.logCamera('构建公共存储路径', details: '存储根目录: $storageRoot, 图片目录: $publicPicturesPath');
      
      // 复制文件到公共存储目录（Pictures/RemoteCam）
      await File(image.path).copy(savedPath);
      _logger.logCamera('文件已保存到公共存储目录', details: savedPath);
      
      // 通知MediaStore扫描新文件（Android 10+需要）
      try {
        await MediaScannerService.scanFile(savedPath);
        _logger.logCamera('已通知MediaStore扫描文件', details: savedPath);
      } catch (e, stackTrace) {
        _logger.logError('MediaStore扫描失败', error: e, stackTrace: stackTrace);
        // 扫描失败不影响主流程
      }
      
      // 记录文件信息到索引
      try {
        final savedFile = File(savedPath);
        final fileSize = await savedFile.length();
        final now = DateTime.now();
        
        await _fileIndex.addFile(
          name: fileName,
          galleryPath: savedPath, // 使用外部存储路径
          fileType: 'image',
          size: fileSize,
          createdTime: now,
          modifiedTime: now,
        );
        _logger.logCamera('文件索引已添加', details: fileName);
      } catch (e, stackTrace) {
        _logger.logError('添加文件索引失败', error: e, stackTrace: stackTrace);
        // 索引失败不影响主流程
      }
      
      await File(image.path).delete();
      _logger.logCamera('临时文件已删除');

      status = CameraStatus.idle;
      _isTakingPhoto = false;
      return savedPath;
    } catch (e, stackTrace) {
      _logger.logError('拍照失败', error: e, stackTrace: stackTrace);
      status = CameraStatus.idle;
      _isTakingPhoto = false;
      rethrow;
    } finally {
      // 释放锁
      completer.complete();
      if (_takePictureLock == completer.future) {
        _takePictureLock = null;
      }
    }
  }

  // 开始录像
  Future<String> startRecording() async {
    if (controller == null || !controller!.value.isInitialized) {
      throw Exception('相机未初始化');
    }

    if (_isRecording) {
      throw Exception('已在录像中');
    }

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = 'VID_$timestamp.mp4';

    _logger.logCamera('开始录像', details: '文件名: $fileName');
    
    // 开始录像（camera包会在cache目录创建临时文件）
    await controller!.startVideoRecording();
    _isRecording = true;
    _currentVideoPath = fileName; // 只保存文件名，不保存路径
    status = CameraStatus.recording;

    _logger.logCamera('录像已开始', details: '文件名: $fileName');
    return fileName;
  }

  // 停止录像
  Future<String> stopRecording() async {
    if (!_isRecording) {
      throw Exception('未在录像中');
    }

    if (_currentVideoPath == null) {
      throw Exception('录像文件名未设置');
    }

    final String fileName = _currentVideoPath!;
    _logger.logCamera('停止录像', details: '文件名: $fileName');
    
    final XFile video = await controller!.stopVideoRecording();
    _isRecording = false;
    status = CameraStatus.idle;

    _logger.logCamera('录像已停止', details: '临时文件: ${video.path}');

    // 等待文件完全写入
    final videoFile = File(video.path);
    int retries = 0;
    while (!await videoFile.exists() && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries++;
    }
    
    if (!await videoFile.exists()) {
      _logger.logError('录像文件不存在', error: Exception('源文件不存在: ${video.path}'));
      throw Exception('录像文件不存在: ${video.path}');
    }
    
    _logger.logCamera('源文件已存在', details: '文件大小: ${await videoFile.length()} bytes');
    
    // 保存到公共存储目录（Movies/RemoteCam）
    // 从应用目录获取外部存储根目录
    final Directory? externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      throw Exception('无法获取外部存储目录');
    }
    
    // 从 /storage/emulated/0/Android/data/.../files 回到 /storage/emulated/0
    final String storageRoot = externalDir.path.split('/Android/data')[0];
    final String publicMoviesPath = path.join(storageRoot, 'Movies', 'RemoteCam');
    await Directory(publicMoviesPath).create(recursive: true);
    final String savedPath = path.join(publicMoviesPath, fileName);
    
    _logger.logCamera('构建公共存储路径', details: '存储根目录: $storageRoot, 视频目录: $publicMoviesPath');
    
    // 复制文件到公共存储目录（Movies/RemoteCam）
    await videoFile.copy(savedPath);
    _logger.logCamera('文件已保存到公共存储目录', details: savedPath);
    
    // 通知MediaStore扫描新文件（Android 10+需要）
    try {
      await MediaScannerService.scanFile(savedPath);
      _logger.logCamera('已通知MediaStore扫描文件', details: savedPath);
    } catch (e, stackTrace) {
      _logger.logError('MediaStore扫描失败', error: e, stackTrace: stackTrace);
      // 扫描失败不影响主流程
    }
    
    // 记录文件信息到索引
    try {
      final savedFile = File(savedPath);
      final fileSize = await savedFile.length();
      final now = DateTime.now();
      
      await _fileIndex.addFile(
        name: fileName,
        galleryPath: savedPath, // 使用外部存储路径
        fileType: 'video',
        size: fileSize,
        createdTime: now,
        modifiedTime: now,
      );
      _logger.logCamera('文件索引已添加', details: fileName);
    } catch (e, stackTrace) {
      _logger.logError('添加文件索引失败', error: e, stackTrace: stackTrace);
      // 索引失败不影响主流程
    }
    
    // 删除临时文件
    try {
      await videoFile.delete();
      _logger.logCamera('临时文件已删除', details: video.path);
    } catch (e) {
      // 忽略删除临时文件失败的错误
      _logger.log('删除临时文件失败: $e', tag: 'CAMERA');
    }

    _currentVideoPath = null;
    _logger.logCamera('录像停止成功', details: savedPath);
    return savedPath;
  }

  // 捕获预览帧（用于实时预览）
  // 现在使用图像流，不会触发闪光灯
  Future<Uint8List?> capturePreviewFrame() async {
    if (controller == null || !controller!.value.isInitialized) {
      // 相机未初始化，返回null
      return null;
    }

    // 如果预览流未启动，启动它
    if (!_isImageStreamActive) {
      _startImageStream();
    }

    // 如果正在录像，返回最后一帧
    if (_isRecording) {
      return _lastPreviewFrame;
    }

    // 如果正在拍照，返回最后一帧，避免冲突
    if (_isTakingPhoto) {
      return _lastPreviewFrame;
    }

    // 直接返回最后一帧（从图像流中获取，不触发闪光灯）
    return _lastPreviewFrame;
  }

  // 获取文件列表（从文件索引读取）
  Future<Map<String, List<FileInfo>>> getFileList() async {
    return await _fileIndex.getFileList();
  }

  // 删除文件（从相册和索引中删除）
  Future<void> deleteFile(String galleryPath) async {
    try {
      // 从相册删除文件
      final file = File(galleryPath);
      if (await file.exists()) {
        await file.delete();
        _logger.logCamera('文件已从相册删除', details: galleryPath);
      }
      
      // 从索引中删除
      await _fileIndex.deleteFile(galleryPath);
    } catch (e, stackTrace) {
      _logger.logError('删除文件失败', error: e, stackTrace: stackTrace);
      throw Exception('删除文件失败: $e');
    }
  }

  // 获取文件（用于下载）
  Future<File> getFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return file;
    } else {
      throw Exception('文件不存在');
    }
  }

  // 释放资源
  void dispose() {
    controller?.dispose();
    controller = null;
  }
}

