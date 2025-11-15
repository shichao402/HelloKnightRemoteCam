import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/camera_status.dart';
import '../models/camera_settings.dart';
import '../models/file_info.dart';
import 'logger_service.dart';
import 'file_index_service.dart';
import 'media_scanner_service.dart';
import 'native_camera_service.dart';

class CameraService {
  CameraStatus status = CameraStatus.idle;
  CameraSettings settings = const CameraSettings();
  final LoggerService _logger = LoggerService();
  final FileIndexService _fileIndex = FileIndexService();
  NativeCameraService? _nativeCamera; // 原生相机服务（用于录制、预览和拍照）
  
  bool _isRecording = false;
  Uint8List? _lastPreviewFrame;
  
  // 互斥锁，确保同一时间只有一个操作调用 takePicture()
  Future<void>? _takePictureLock;
  
  // 初始化文件索引服务
  Future<void> initializeFileIndex() async {
    await _fileIndex.initialize();
  }

  bool get isRecording => _isRecording;
  bool get isInitialized => _nativeCamera?.isInitialized ?? false;
  Uint8List? get lastPreviewFrame => _lastPreviewFrame;

  /// 恢复预览流（应用切回前台时调用）
  Future<void> resumePreview() async {
    if (_nativeCamera != null && _nativeCamera!.isInitialized) {
      await _nativeCamera!.resumePreview();
    }
  }
  
  /// 设置检查活跃客户端连接的回调函数（用于控制预览帧处理）
  void setHasActiveClientsCallback(bool Function()? callback) {
    _nativeCamera?.setHasActiveClientsCallback(callback);
  }

  // 初始化相机
  // camera: 主相机（使用原生相机进行录制、预览和拍照）
  Future<void> initialize(CameraDescription camera, [CameraSettings? initialSettings]) async {
    if (initialSettings != null) {
      settings = initialSettings;
    }

    // 初始化原生相机服务（用于录制、预览和拍照，支持同时进行）
    _nativeCamera = NativeCameraService();
    _nativeCamera!.onPreviewFrame = (Uint8List frame) {
      _lastPreviewFrame = frame;
    };
    
    // 获取相机ID（camera.name通常是数字字符串，如"0", "1"）
    final cameraId = camera.name;
    final success = await _nativeCamera!.initialize(
      cameraId,
      previewWidth: 640,
      previewHeight: 480,
    );
    
    if (!success) {
      _nativeCamera?.release();
      _nativeCamera = null;
      throw Exception('原生相机初始化失败：返回false');
    }
    
    _logger.logCamera('原生相机初始化成功', details: '相机ID: $cameraId');
    _logger.logCamera('原生相机支持同时录制和预览', details: '');
    
    status = CameraStatus.idle;
  }
  
  // 重新配置相机（用于更改设置）
  Future<void> reconfigure(CameraSettings newSettings, CameraDescription camera) async {
    if (status == CameraStatus.recording) {
      throw Exception('录像中无法更改设置');
    }

    status = CameraStatus.reconfiguring;
    settings = newSettings;
    
    // 原生相机不需要重新配置，设置更改会在下次操作时生效
    status = CameraStatus.idle;
  }

  // 拍照
  Future<String> takePicture() async {
    // 检查相机是否已初始化
    if (!isInitialized) {
      _logger.logError('拍照失败', error: Exception('相机未初始化'));
      throw Exception('相机未初始化');
    }

    _logger.logCamera('开始拍照', details: '');

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

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'IMG_$timestamp.jpg';

      _logger.logCamera('调用takePicture', details: '文件名: $fileName');

      // 使用原生相机拍照
      if (_nativeCamera == null || !_nativeCamera!.isInitialized) {
        completer.complete();
        throw Exception('原生相机未初始化');
      }

      // 获取图片保存路径
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        completer.complete();
        throw Exception('无法获取外部存储目录');
      }
      
      final storageRoot = externalDir.path.split('/Android')[0];
      final picturesDir = Directory(path.join(storageRoot, 'Pictures', 'RemoteCam'));
      if (!await picturesDir.exists()) {
        await picturesDir.create(recursive: true);
      }
      
      final savedPath = path.join(picturesDir.path, fileName);
      
      final picturePath = await _nativeCamera!.takePicture(savedPath);
      if (picturePath == null || picturePath.isEmpty) {
        completer.complete();
        throw Exception('原生相机拍照失败：返回null或空路径');
      }
      
      _logger.logCamera('拍照成功', details: '文件路径: $picturePath');
      
      // 通知MediaStore扫描新文件
      try {
        await MediaScannerService.scanFile(picturePath);
        _logger.logCamera('已通知MediaStore扫描文件', details: picturePath);
      } catch (e, stackTrace) {
        _logger.logError('MediaStore扫描失败', error: e, stackTrace: stackTrace);
      }
      
      // 添加到文件索引
      try {
        final savedFile = File(picturePath);
        final fileSize = await savedFile.length();
        final now = DateTime.now();
        
        await _fileIndex.addFile(
          name: fileName,
          galleryPath: picturePath,
          fileType: 'image',
          size: fileSize,
          createdTime: now,
          modifiedTime: now,
        );
        _logger.logCamera('文件索引已添加', details: fileName);
      } catch (e, stackTrace) {
        _logger.logError('添加文件索引失败', error: e, stackTrace: stackTrace);
      }
      
      status = CameraStatus.idle;
      completer.complete();
      return picturePath;
    } catch (e, stackTrace) {
      _logger.logError('拍照失败', error: e, stackTrace: stackTrace);
      status = CameraStatus.idle;
      // 如果completer还没有完成，在这里完成它
      if (!completer.isCompleted) {
        completer.complete();
      }
      rethrow;
    } finally {
      // 释放锁（如果completer还没有完成）
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (_takePictureLock == completer.future) {
        _takePictureLock = null;
      }
    }
  }

  // 开始录像
  Future<String> startRecording() async {
    if (!isInitialized) {
      throw Exception('相机未初始化');
    }

    if (_isRecording) {
      throw Exception('已在录像中');
    }

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = 'VID_$timestamp.mp4';

    _logger.logCamera('开始录像', details: '文件名: $fileName');
    
    if (_nativeCamera == null || !_nativeCamera!.isInitialized) {
      throw Exception('原生相机未初始化');
    }
    
    // 获取视频保存路径
    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      throw Exception('无法获取外部存储目录');
    }
    
    final storageRoot = externalDir.path.split('/Android')[0];
    final videoDir = Directory(path.join(storageRoot, 'Movies', 'RemoteCam'));
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    
    final videoPath = path.join(videoDir.path, fileName);
    
    final success = await _nativeCamera!.startRecording(videoPath);
    if (!success) {
      throw Exception('原生相机开始录制失败');
    }
    
    _isRecording = true;
    status = CameraStatus.recording;
    _logger.logCamera('录像已开始', details: '文件路径: $videoPath');
    _logger.logCamera('原生相机支持同时录制和预览', details: '预览将继续更新');
    
    return fileName;
  }

  // 停止录像
  Future<String> stopRecording() async {
    if (!_isRecording) {
      throw Exception('未在录像中');
    }

    if (_nativeCamera == null || !_nativeCamera!.isRecording) {
      throw Exception('原生相机未在录制中');
    }

    _logger.logCamera('停止录像', details: '');
    
    final savedPath = await _nativeCamera!.stopRecording();
    if (savedPath == null || savedPath.isEmpty) {
      throw Exception('原生相机停止录制返回null或空路径');
    }
    
    _isRecording = false;
    status = CameraStatus.idle;
    
    _logger.logCamera('录像已停止', details: '文件路径: $savedPath');
    _logger.logCamera('原生相机预览继续运行', details: '预览未中断');
    
    // 等待文件完全写入（使用指数退避策略，最多等待2秒）
    final videoFile = File(savedPath);
    int retries = 0;
    int delayMs = 50; // 初始延迟50ms
    const maxRetries = 20; // 最多重试20次（总共约2秒）
    
    while (!await videoFile.exists() && retries < maxRetries) {
      await Future.delayed(Duration(milliseconds: delayMs));
      retries++;
      // 指数退避：前几次快速检查，后面逐渐增加延迟
      if (retries < 5) {
        delayMs = 50;
      } else if (retries < 10) {
        delayMs = 100;
      } else {
        delayMs = 200;
      }
    }
    
    if (!await videoFile.exists()) {
      _logger.logError('录像文件不存在', error: Exception('文件不存在: $savedPath'));
      throw Exception('录像文件不存在: $savedPath');
    }
    
    // 等待文件大小稳定（确保文件写入完成）
    int lastSize = 0;
    int stableCount = 0;
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      final currentSize = await videoFile.length();
      if (currentSize == lastSize && currentSize > 0) {
        stableCount++;
        if (stableCount >= 2) {
          break; // 文件大小连续2次相同，认为写入完成
        }
      } else {
        stableCount = 0;
        lastSize = currentSize;
      }
    }
    
    _logger.logCamera('录像文件已存在', details: '文件大小: ${await videoFile.length()} bytes');
    
    final String fileName = path.basename(savedPath);
    
    // 通知MediaStore扫描新文件（Android 10+需要）
    try {
      await MediaScannerService.scanFile(savedPath);
      _logger.logCamera('已通知MediaStore扫描文件', details: savedPath);
    } catch (e, stackTrace) {
      _logger.logError('MediaStore扫描失败', error: e, stackTrace: stackTrace);
    }
    
    // 添加到文件索引
    try {
      final fileSize = await videoFile.length();
      final now = DateTime.now();
      await _fileIndex.addFile(
        name: fileName,
        galleryPath: savedPath,
        fileType: 'video',
        size: fileSize,
        createdTime: now,
        modifiedTime: now,
      );
      _logger.logCamera('已添加到文件索引', details: '文件名: $fileName');
    } catch (e, stackTrace) {
      _logger.logError('添加文件索引失败', error: e, stackTrace: stackTrace);
    }
    
    _logger.logCamera('录像停止成功', details: savedPath);
    return savedPath;
  }

  // 捕获预览帧（用于实时预览）
  Future<Uint8List?> capturePreviewFrame() async {
    if (_nativeCamera == null || !_nativeCamera!.isInitialized) {
      _logger.log('预览帧获取失败：原生相机未初始化', tag: 'PREVIEW');
      return null;
    }
    
    final frame = _nativeCamera!.getLastPreviewFrame();
    if (frame == null) {
      _logger.log('原生相机预览帧为null', tag: 'PREVIEW');
    }
    return frame;
  }

  // 获取文件列表（从文件索引读取，支持分页和增量获取）
  Future<Map<String, dynamic>> getFileList({
    int? page,
    int? pageSize,
    int? since,
  }) async {
    return await _fileIndex.getFileList(
      page: page,
      pageSize: pageSize,
      since: since,
    );
  }
  
  // 获取文件列表（兼容旧接口）
  Future<Map<String, List<FileInfo>>> getFileListLegacy() async {
    return await _fileIndex.getFileListLegacy();
  }

  // 根据文件名获取文件信息
  Future<FileInfo?> getFileByName(String fileName) async {
    return await _fileIndex.getFileByName(fileName);
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
  Future<void> dispose() async {
    // 释放原生相机资源
    await _nativeCamera?.release();
    _nativeCamera = null;
  }
}

