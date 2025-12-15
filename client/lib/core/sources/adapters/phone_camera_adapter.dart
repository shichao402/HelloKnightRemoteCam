import 'dart:async';
import 'dart:typed_data';
import '../base/sources_base.dart';
import '../../../services/api_service.dart';
import '../../../models/file_info.dart';
import '../../../models/camera_settings.dart';
import '../../../services/logger_service.dart';

/// 手机相机配置
class PhoneCameraConfig implements SourceConfig {
  @override
  final String id;

  @override
  final String name;

  @override
  SourceType get type => SourceType.phoneCamera;

  final String host;
  final int port;

  const PhoneCameraConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'host': host,
        'port': port,
      };

  factory PhoneCameraConfig.fromJson(Map<String, dynamic> json) {
    return PhoneCameraConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
    );
  }
}

/// 手机相机适配器
///
/// 将现有的 ApiService 封装为数据源适配器
class PhoneCameraAdapter
    implements SourceAdapter, CaptureCapability, StreamCapability, FileSourceCapability {
  final PhoneCameraConfig config;
  final ClientLoggerService _logger = ClientLoggerService();

  late final ApiService _apiService;

  SourceStatus _status = SourceStatus.disconnected;
  SourceError? _lastError;
  bool _isRecording = false;

  final _statusController = StreamController<SourceStatus>.broadcast();
  final _recordingController = StreamController<bool>.broadcast();
  final _captureController = StreamController<CaptureResult>.broadcast();
  final _newFilesController = StreamController<List<RemoteFileInfo>>.broadcast();

  StreamSubscription? _notificationSubscription;

  PhoneCameraAdapter({required this.config}) {
    _apiService = ApiService(host: config.host, port: config.port);
  }

  /// 从现有 ApiService 创建适配器
  factory PhoneCameraAdapter.fromApiService(ApiService apiService, {String? name}) {
    final config = PhoneCameraConfig(
      id: 'phone_${apiService.host}_${apiService.port}',
      name: name ?? '手机相机 (${apiService.host})',
      host: apiService.host,
      port: apiService.port,
    );
    final adapter = PhoneCameraAdapter(config: config);
    adapter._apiService = apiService;
    return adapter;
  }

  // ==================== SourceAdapter 实现 ====================

  @override
  String get id => config.id;

  @override
  String get name => config.name;

  @override
  SourceType get type => SourceType.phoneCamera;

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
      final error = await _apiService.ping();
      if (error != null) {
        _lastError = SourceError(
          code: error.code.name,
          message: error.message,
          details: error.details,
        );
        _setStatus(SourceStatus.error);
        return;
      }

      // 监听 WebSocket 通知
      _setupNotificationListener();

      _setStatus(SourceStatus.connected);
      _logger.log('手机相机已连接: ${config.host}:${config.port}', tag: 'SOURCE');
    } catch (e) {
      _lastError = SourceError.fromException(e);
      _setStatus(SourceStatus.error);
      _logger.logError('手机相机连接失败', error: e);
    }
  }

  @override
  Future<void> disconnect() async {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;

    await _apiService.gracefulDisconnect();
    _setStatus(SourceStatus.disconnected);
    _logger.log('手机相机已断开: ${config.host}:${config.port}', tag: 'SOURCE');
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _apiService.dispose();
    _statusController.close();
    _recordingController.close();
    _captureController.close();
    _newFilesController.close();
  }

  void _setStatus(SourceStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  void _setupNotificationListener() {
    _notificationSubscription?.cancel();
    final notifications = _apiService.webSocketNotifications;
    if (notifications != null) {
      _notificationSubscription = notifications.listen(_handleNotification);
    }
  }

  void _handleNotification(Map<String, dynamic> notification) {
    final event = notification['event'] as String?;
    final data = notification['data'] as Map<String, dynamic>?;

    switch (event) {
      case 'new_files':
        _handleNewFiles(data);
        break;
      case 'recording_started':
        _isRecording = true;
        _recordingController.add(true);
        break;
      case 'recording_stopped':
        _isRecording = false;
        _recordingController.add(false);
        break;
      case 'connection_failed':
        _lastError = SourceError(
          code: data?['reason'] as String? ?? 'unknown',
          message: data?['message'] as String? ?? '连接失败',
        );
        _setStatus(SourceStatus.error);
        break;
    }
  }

  void _handleNewFiles(Map<String, dynamic>? data) {
    if (data == null) return;

    final files = <RemoteFileInfo>[];
    final pictures = data['pictures'] as List?;
    final videos = data['videos'] as List?;

    if (pictures != null) {
      for (final p in pictures) {
        if (p is Map<String, dynamic>) {
          files.add(_fileInfoToRemoteFileInfo(FileInfo.fromJson(p), false));
        }
      }
    }

    if (videos != null) {
      for (final v in videos) {
        if (v is Map<String, dynamic>) {
          files.add(_fileInfoToRemoteFileInfo(FileInfo.fromJson(v), true));
        }
      }
    }

    if (files.isNotEmpty) {
      _newFilesController.add(files);
    }
  }

  RemoteFileInfo _fileInfoToRemoteFileInfo(FileInfo info, bool isVideo) {
    return RemoteFileInfo(
      path: info.path,
      name: info.name,
      size: info.size,
      createdTime: info.createdTime,
      modifiedTime: info.modifiedTime,
      isVideo: isVideo,
      isStarred: info.isStarred,
    );
  }

  // ==================== CaptureCapability 实现 ====================

  @override
  Future<CaptureResult> capture() async {
    try {
      final result = await _apiService.capture();
      if (result['success'] == true) {
        final captureResult = CaptureResult.success(
          remotePath: result['path'] as String?,
          fileName: result['fileName'] as String?,
          fileSize: result['size'] as int?,
          isVideo: false,
        );
        _captureController.add(captureResult);
        return captureResult;
      } else {
        return CaptureResult.failure(result['error'] as String? ?? '拍照失败');
      }
    } catch (e) {
      return CaptureResult.failure(e.toString());
    }
  }

  @override
  Future<bool> startRecording() async {
    try {
      final result = await _apiService.startRecording();
      if (result['success'] == true) {
        _isRecording = true;
        _recordingController.add(true);
        return true;
      }
      return false;
    } catch (e) {
      _logger.logError('开始录像失败', error: e);
      return false;
    }
  }

  @override
  Future<CaptureResult> stopRecording() async {
    try {
      final result = await _apiService.stopRecording();
      _isRecording = false;
      _recordingController.add(false);

      if (result['success'] == true) {
        final captureResult = CaptureResult.success(
          remotePath: result['path'] as String?,
          fileName: result['fileName'] as String?,
          fileSize: result['size'] as int?,
          isVideo: true,
        );
        _captureController.add(captureResult);
        return captureResult;
      } else {
        return CaptureResult.failure(result['error'] as String? ?? '停止录像失败');
      }
    } catch (e) {
      _isRecording = false;
      _recordingController.add(false);
      return CaptureResult.failure(e.toString());
    }
  }

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<bool> get recordingStream => _recordingController.stream;

  @override
  CaptureSettings get settings => const CaptureSettings();

  @override
  Future<bool> updateSettings(CaptureSettings settings) async {
    try {
      final cameraSettings = CameraSettings();
      final result = await _apiService.updateSettings(cameraSettings);
      return result['success'] == true;
    } catch (e) {
      _logger.logError('更新设置失败', error: e);
      return false;
    }
  }

  @override
  Stream<CaptureResult> get captureStream => _captureController.stream;

  // ==================== StreamCapability 实现 ====================

  @override
  Future<String?> getPreviewStreamUrl() async {
    try {
      return await _apiService.getPreviewStreamUrl();
    } catch (e) {
      _logger.logError('获取预览流 URL 失败', error: e);
      return null;
    }
  }

  @override
  Future<void> startPreview() async {
    // 预览通过 URL 流式传输，无需额外操作
  }

  @override
  Future<void> stopPreview() async {
    // 预览通过 URL 流式传输，无需额外操作
  }

  @override
  bool get isPreviewing => isConnected;

  @override
  Stream<Uint8List>? get previewFrameStream => null; // 使用 URL 流式预览

  // ==================== FileSourceCapability 实现 ====================

  @override
  Future<FileListResult> getFileList({
    int? page,
    int? pageSize,
    DateTime? since,
  }) async {
    try {
      final result = await _apiService.getFileList(
        page: page,
        pageSize: pageSize,
        since: since?.millisecondsSinceEpoch,
      );

      if (result['success'] == true) {
        final files = <RemoteFileInfo>[];

        final pictures = result['pictures'] as List?;
        final videos = result['videos'] as List?;

        if (pictures != null) {
          for (final p in pictures) {
            if (p is FileInfo) {
              files.add(_fileInfoToRemoteFileInfo(p, false));
            }
          }
        }

        if (videos != null) {
          for (final v in videos) {
            if (v is FileInfo) {
              files.add(_fileInfoToRemoteFileInfo(v, true));
            }
          }
        }

        return FileListResult.success(
          files: files,
          total: result['total'] as int? ?? files.length,
          page: result['page'] as int? ?? 1,
          hasMore: result['hasMore'] as bool? ?? false,
        );
      } else {
        return FileListResult.failure(result['error'] as String? ?? '获取文件列表失败');
      }
    } catch (e) {
      return FileListResult.failure(e.toString());
    }
  }

  @override
  String getFileDownloadUrl(String remotePath) {
    return _apiService.getFileDownloadUrl(remotePath);
  }

  @override
  Future<String> getThumbnailUrl(String remotePath, {bool isVideo = false}) async {
    return await _apiService.getThumbnailUrl(remotePath, isVideo);
  }

  @override
  Future<bool> deleteRemoteFile(String remotePath) async {
    try {
      final result = await _apiService.deleteFile(remotePath);
      return result['success'] == true;
    } catch (e) {
      _logger.logError('删除远程文件失败', error: e);
      return false;
    }
  }

  @override
  Future<bool> toggleStarred(String remotePath) async {
    try {
      final result = await _apiService.toggleStarred(remotePath);
      return result['success'] == true;
    } catch (e) {
      _logger.logError('切换星标失败', error: e);
      return false;
    }
  }

  @override
  Stream<List<RemoteFileInfo>>? get newFilesStream => _newFilesController.stream;

  // ==================== 扩展方法 ====================

  /// 获取底层 ApiService（用于需要直接访问的场景）
  ApiService get apiService => _apiService;

  /// 获取相机能力信息
  Future<Map<String, dynamic>> getCameraCapabilities(String cameraId) async {
    return await _apiService.getCameraCapabilities(cameraId);
  }

  /// 获取所有相机能力信息
  Future<Map<String, dynamic>> getAllCameraCapabilities() async {
    return await _apiService.getAllCameraCapabilities();
  }

  /// 获取设备信息
  Future<Map<String, dynamic>> getDeviceInfo() async {
    return await _apiService.getDeviceInfo();
  }
}
