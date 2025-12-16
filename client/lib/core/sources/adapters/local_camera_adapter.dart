import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart' as cam;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
// 隐藏与 camera 包冲突的类型，使用 capture_controller.dart 中定义的版本
import '../base/sources_base.dart' hide FlashMode;
import '../base/capture_controller.dart' show FlashMode, CameraPosition;
import '../../../services/logger_service.dart';

/// 本地摄像头配置
class LocalCameraConfig implements SourceConfig {
  @override
  final String id;

  @override
  final String name;

  @override
  SourceType get type => SourceType.localCamera;

  /// 首选摄像头位置
  final CameraPosition preferredPosition;

  /// 首选分辨率
  final cam.ResolutionPreset resolutionPreset;

  const LocalCameraConfig({
    this.id = 'local_camera',
    this.name = '本地摄像头',
    this.preferredPosition = CameraPosition.back,
    this.resolutionPreset = cam.ResolutionPreset.high,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'preferredPosition': preferredPosition.name,
        'resolutionPreset': resolutionPreset.name,
      };
}

/// 本地摄像头适配器
///
/// 使用 camera 插件实现本地摄像头拍摄
class LocalCameraAdapter
    implements SourceAdapter, CaptureCapability, StreamCapability {
  final LocalCameraConfig config;
  final ClientLoggerService _logger = ClientLoggerService();

  cam.CameraController? _cameraController;
  List<cam.CameraDescription>? _cameras;
  int _currentCameraIndex = 0;

  SourceStatus _status = SourceStatus.disconnected;
  SourceError? _lastError;
  bool _isRecording = false;
  bool _isPreviewing = false;

  final _statusController = StreamController<SourceStatus>.broadcast();
  final _recordingController = StreamController<bool>.broadcast();
  final _captureController = StreamController<CaptureResult>.broadcast();
  final _previewFrameController = StreamController<Uint8List>.broadcast();

  LocalCameraAdapter({this.config = const LocalCameraConfig()});

  // ==================== SourceAdapter 实现 ====================

  @override
  String get id => config.id;

  @override
  String get name => config.name;

  @override
  SourceType get type => SourceType.localCamera;

  @override
  SourceStatus get status => _status;

  @override
  Stream<SourceStatus> get statusStream => _statusController.stream;

  @override
  SourceError? get lastError => _lastError;

  @override
  bool get isConnected => _status == SourceStatus.connected;

  @override
  Future<void> connect() async {
    if (_status == SourceStatus.connecting || _status == SourceStatus.connected) {
      return;
    }

    _setStatus(SourceStatus.connecting);
    _lastError = null;

    try {
      // 获取可用摄像头列表
      _cameras = await cam.availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _lastError = const SourceError(
          code: 'no_camera',
          message: '未找到可用的摄像头',
        );
        _setStatus(SourceStatus.error);
        return;
      }

      // 选择首选摄像头
      _currentCameraIndex = _findPreferredCamera();

      // 初始化摄像头控制器
      await _initializeCamera();

      _setStatus(SourceStatus.connected);
      _logger.log('本地摄像头已连接: ${_cameras![_currentCameraIndex].name}', tag: 'SOURCE');
    } catch (e) {
      _lastError = SourceError.fromException(e);
      _setStatus(SourceStatus.error);
      _logger.logError('本地摄像头连接失败', error: e);
    }
  }

  int _findPreferredCamera() {
    if (_cameras == null || _cameras!.isEmpty) return 0;

    final preferredLensDirection = config.preferredPosition == CameraPosition.front
        ? cam.CameraLensDirection.front
        : cam.CameraLensDirection.back;

    for (int i = 0; i < _cameras!.length; i++) {
      if (_cameras![i].lensDirection == preferredLensDirection) {
        return i;
      }
    }
    return 0;
  }

  Future<void> _initializeCamera() async {
    if (_cameras == null || _cameras!.isEmpty) return;

    // 释放之前的控制器
    await _cameraController?.dispose();

    _cameraController = cam.CameraController(
      _cameras![_currentCameraIndex],
      config.resolutionPreset,
      enableAudio: true,
      imageFormatGroup: cam.ImageFormatGroup.jpeg,
    );

    await _cameraController!.initialize();
    _logger.log('摄像头初始化完成: ${_cameras![_currentCameraIndex].name}', tag: 'CAMERA');
  }

  @override
  Future<void> disconnect() async {
    await stopPreview();
    if (_isRecording) {
      await stopRecording();
    }
    await _cameraController?.dispose();
    _cameraController = null;
    _setStatus(SourceStatus.disconnected);
    _logger.log('本地摄像头已断开', tag: 'SOURCE');
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _statusController.close();
    _recordingController.close();
    _captureController.close();
    _previewFrameController.close();
  }

  void _setStatus(SourceStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  // ==================== CaptureCapability 实现 ====================

  @override
  Future<CaptureResult> capture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return CaptureResult.failure('摄像头未初始化');
    }

    if (_isRecording) {
      return CaptureResult.failure('正在录像中，无法拍照');
    }

    try {
      final cam.XFile file = await _cameraController!.takePicture();

      // 移动到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final captureDir = Directory(path.join(appDir.path, 'Captures'));
      if (!await captureDir.exists()) {
        await captureDir.create(recursive: true);
      }

      final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newPath = path.join(captureDir.path, fileName);
      await File(file.path).copy(newPath);

      // 删除临时文件
      try {
        await File(file.path).delete();
      } catch (_) {}

      final fileInfo = await File(newPath).stat();

      final result = CaptureResult.success(
        localPath: newPath,
        fileName: fileName,
        fileSize: fileInfo.size,
        isVideo: false,
      );

      _captureController.add(result);
      _logger.log('拍照成功: $fileName', tag: 'CAMERA');

      return result;
    } catch (e) {
      _logger.logError('拍照失败', error: e);
      return CaptureResult.failure(e.toString());
    }
  }

  @override
  Future<bool> startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return false;
    }

    if (_isRecording) {
      return false;
    }

    try {
      await _cameraController!.startVideoRecording();
      _isRecording = true;
      _recordingController.add(true);
      _logger.log('开始录像', tag: 'CAMERA');
      return true;
    } catch (e) {
      _logger.logError('开始录像失败', error: e);
      return false;
    }
  }

  @override
  Future<CaptureResult> stopRecording() async {
    if (_cameraController == null || !_isRecording) {
      return CaptureResult.failure('未在录像中');
    }

    try {
      final cam.XFile file = await _cameraController!.stopVideoRecording();
      _isRecording = false;
      _recordingController.add(false);

      // 移动到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final captureDir = Directory(path.join(appDir.path, 'Captures'));
      if (!await captureDir.exists()) {
        await captureDir.create(recursive: true);
      }

      final fileName = 'VID_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final newPath = path.join(captureDir.path, fileName);
      await File(file.path).copy(newPath);

      // 删除临时文件
      try {
        await File(file.path).delete();
      } catch (_) {}

      final fileInfo = await File(newPath).stat();

      final result = CaptureResult.success(
        localPath: newPath,
        fileName: fileName,
        fileSize: fileInfo.size,
        isVideo: true,
      );

      _captureController.add(result);
      _logger.log('录像完成: $fileName', tag: 'CAMERA');

      return result;
    } catch (e) {
      _isRecording = false;
      _recordingController.add(false);
      _logger.logError('停止录像失败', error: e);
      return CaptureResult.failure(e.toString());
    }
  }

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<bool> get recordingStream => _recordingController.stream;

  @override
  CaptureSettings get settings => CaptureSettings(
        cameraId: _cameras?[_currentCameraIndex].name,
      );

  @override
  Future<bool> updateSettings(CaptureSettings settings) async {
    // 本地摄像头设置更新
    return true;
  }

  @override
  Stream<CaptureResult> get captureStream => _captureController.stream;

  // ==================== StreamCapability 实现 ====================

  @override
  Future<String?> getPreviewStreamUrl() async {
    // 本地摄像头不支持 URL 流式预览
    return null;
  }

  @override
  Future<void> startPreview() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    _isPreviewing = true;
    _logger.log('开始预览', tag: 'CAMERA');
  }

  @override
  Future<void> stopPreview() async {
    _isPreviewing = false;
    _logger.log('停止预览', tag: 'CAMERA');
  }

  @override
  bool get isPreviewing => _isPreviewing;

  @override
  Stream<Uint8List>? get previewFrameStream => _previewFrameController.stream;

  // ==================== 扩展方法 ====================

  /// 获取摄像头控制器（用于预览 Widget）
  cam.CameraController? get cameraController => _cameraController;

  /// 获取可用摄像头列表
  List<cam.CameraDescription>? get cameras => _cameras;

  /// 当前摄像头索引
  int get currentCameraIndex => _currentCameraIndex;

  /// 切换摄像头
  Future<bool> switchCamera() async {
    if (_cameras == null || _cameras!.length <= 1) {
      return false;
    }

    try {
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras!.length;
      await _initializeCamera();
      _logger.log('切换到摄像头: ${_cameras![_currentCameraIndex].name}', tag: 'CAMERA');
      return true;
    } catch (e) {
      _logger.logError('切换摄像头失败', error: e);
      return false;
    }
  }

  /// 设置闪光灯模式
  Future<bool> setFlashMode(FlashMode mode) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return false;
    }

    try {
      // 转换为 camera 包的 FlashMode
      final camFlashMode = _toCamFlashMode(mode);
      await _cameraController!.setFlashMode(camFlashMode);
      return true;
    } catch (e) {
      _logger.logError('设置闪光灯失败', error: e);
      return false;
    }
  }

  cam.FlashMode _toCamFlashMode(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return cam.FlashMode.off;
      case FlashMode.on:
        return cam.FlashMode.always;
      case FlashMode.auto:
        return cam.FlashMode.auto;
      case FlashMode.torch:
        return cam.FlashMode.torch;
    }
  }

  /// 设置缩放级别
  Future<bool> setZoom(double zoom) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return false;
    }

    try {
      await _cameraController!.setZoomLevel(zoom);
      return true;
    } catch (e) {
      _logger.logError('设置缩放失败', error: e);
      return false;
    }
  }
}
