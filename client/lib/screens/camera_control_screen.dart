import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import '../services/api_service.dart';
import '../services/api_service_manager.dart';
import '../services/download_manager.dart';
import '../services/websocket_connection.dart' as ws;
import '../models/file_info.dart';
import '../models/download_task.dart';
import '../widgets/transformed_preview_widget.dart';
import '../services/orientation_preferences_service.dart';
import 'settings_selection_screen.dart';
import 'download_manager_screen.dart';
import 'library/library_screen.dart';
import 'package:path/path.dart' as path;
import '../services/logger_service.dart';
import '../services/download_settings_service.dart';
import '../models/connection_error.dart';
import '../core/core.dart';

class CameraControlScreen extends StatefulWidget {
  final ApiService apiService;

  const CameraControlScreen({Key? key, required this.apiService})
      : super(key: key);

  @override
  State<CameraControlScreen> createState() => _CameraControlScreenState();
}

class _CameraControlScreenState extends State<CameraControlScreen> {
  bool _isRecording = false;
  bool _isOperating = false;
  List<FileInfo> _pictures = [];
  List<FileInfo> _videos = [];
  late DownloadManager _downloadManager;
  StreamSubscription<List<DownloadTask>>? _downloadSubscription;
  final DownloadSettingsService _downloadSettings = DownloadSettingsService();
  final Map<String, bool> _downloadedStatusCache = {}; // 缓存下载状态

  // 连接状态管理（监听 WebSocketConnection 的状态）
  StreamSubscription<ws.ConnectionStateChange>? _connectionStateSubscription;
  StreamSubscription? _webSocketSubscription; // WebSocket通知消息订阅
  final ClientLoggerService _logger = ClientLoggerService();
  
  // 当前连接状态（从 WebSocketConnection 同步）
  ws.ConnectionState _connectionState = ws.ConnectionState.disconnected;
  int _reconnectAttempts = 0;

  // 设备方向（0=竖屏, 90=横屏右转, 180=倒置, 270=横屏左转）
  // 使用ValueNotifier，只更新预览部分，不影响文件列表
  final ValueNotifier<int> _deviceOrientationNotifier = ValueNotifier<int>(0);

  // 方向锁定状态（true=锁定，使用固定方向；false=解锁，使用重力感应）
  bool _orientationLocked = true; // 默认锁定

  // 锁定状态下的手动旋转角度（0, 90, 180, 270度）
  int _lockedRotationAngle = 0; // 默认0度（竖屏）

  // 传感器方向（从服务器获取，用于计算预览旋转角度）
  int _sensorOrientation = 0;

  // 预览尺寸（从服务器获取，默认640x480）
  final ValueNotifier<Map<String, int>> _previewSizeNotifier =
      ValueNotifier<Map<String, int>>({'width': 640, 'height': 480});

  // 转置后的预览尺寸（根据旋转角度计算）
  final ValueNotifier<Map<String, int>> _transformedPreviewSizeNotifier =
      ValueNotifier<Map<String, int>>({'width': 640, 'height': 480});

  // 预览初始化状态
  bool _previewInitialized = false;
  int _previewInitKey = 0; // 用于强制重建预览组件

  /// 统一更新预览尺寸的方法
  /// 从服务器返回的预览尺寸数据中提取并更新本地状态
  void _updatePreviewSize(Map<String, dynamic>? previewSizeData) {
    if (previewSizeData == null) {
      _logger.log('预览尺寸数据为null，跳过更新', tag: 'PREVIEW');
      return;
    }

    final width = previewSizeData['width'] as int?;
    final height = previewSizeData['height'] as int?;

    if (width == null || height == null) {
      _logger.log('预览尺寸数据不完整: width=$width, height=$height，跳过更新', tag: 'PREVIEW');
      return;
    }

    // 检查是否与当前值相同，避免不必要的更新
    final currentSize = _previewSizeNotifier.value;
    if (currentSize['width'] == width && currentSize['height'] == height) {
      _logger.log('预览尺寸未变化: ${width}x${height}，跳过更新', tag: 'PREVIEW');
      return;
    }

    if (mounted) {
      _previewSizeNotifier.value = {
        'width': width,
        'height': height,
      };
      _logger.log('更新预览尺寸: ${width}x${height} (之前: ${currentSize['width']}x${currentSize['height']})', tag: 'PREVIEW');
      
      // 预览尺寸更新后，自动更新转置后的尺寸
      _updateTransformedPreviewSize();
    }
  }

  // 当前旋转角度（0-360度），用于客户端旋转预览流
  final ValueNotifier<int> _rotationAngleNotifier = ValueNotifier<int>(0);

  // 方向偏好设置服务
  final OrientationPreferencesService _orientationPrefs =
      OrientationPreferencesService();

  // 预览流URL（异步获取，包含版本号）
  String? _previewStreamUrl;

  @override
  void initState() {
    super.initState();
    // 注册到全局管理器，以便在应用退出时能够优雅关闭
    ApiServiceManager().setCurrentApiService(widget.apiService);

    _downloadManager = DownloadManager(baseUrl: widget.apiService.baseUrl);
    _downloadManager.initialize();
    _refreshFileList();
    
    // 监听连接状态变化
    _startListeningConnectionState();
    
    // 启动WebSocket连接并监听通知
    _startFileListRefreshTimer();
    // 连接WebSocket（用于API调用）
    widget.apiService.connectWebSocket();
    // 初始化方向锁定状态（默认锁定）
    _initializeOrientationLock();
    // 异步获取预览流URL（包含版本号）
    _loadPreviewStreamUrl();
    
    // 初始化连接状态
    _connectionState = widget.apiService.connectionState;
  }
  
  /// 开始监听连接状态变化
  void _startListeningConnectionState() {
    _connectionStateSubscription = widget.apiService.connectionStateStream.listen(
      (stateChange) {
        if (!mounted) return;
        
        final oldState = stateChange.oldState;
        final newState = stateChange.newState;
        
        _logger.log('连接状态变化: $oldState -> $newState', tag: 'CONNECTION');
        
        setState(() {
          _connectionState = newState;
          // 更新重连次数
          if (stateChange.data != null && stateChange.data!['attempt'] != null) {
            _reconnectAttempts = stateChange.data!['attempt'] as int;
          }
        });
        
        // 处理状态变化
        _handleConnectionStateChange(oldState, newState, stateChange.error);
      },
      onError: (error) {
        _logger.logError('连接状态流错误', error: error);
      },
    );
  }
  
  /// 处理连接状态变化
  void _handleConnectionStateChange(
    ws.ConnectionState oldState, 
    ws.ConnectionState newState, 
    ConnectionError? error,
  ) {
    // 从断开/重连状态恢复到已注册状态
    if (newState == ws.ConnectionState.registered && 
        (oldState == ws.ConnectionState.disconnected || 
         oldState == ws.ConnectionState.reconnecting ||
         oldState == ws.ConnectionState.connected)) {
      _logger.log('连接已恢复，刷新数据', tag: 'CONNECTION');
      _onConnectionRestored();
    }
    
    // 认证失败，返回登录界面
    if (error != null && _isAuthFailureError(error)) {
      _logger.log('认证失败: ${error.message}', tag: 'CONNECTION');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.getUserFriendlyMessage()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
  }
  
  /// 检查是否是认证失败错误
  bool _isAuthFailureError(ConnectionError error) {
    return error.code == ConnectionErrorCode.versionIncompatible ||
           error.code == ConnectionErrorCode.authenticationFailed ||
           error.code == ConnectionErrorCode.serverVersionTooLow;
  }
  
  /// 连接恢复后的处理
  void _onConnectionRestored() {
    _refreshFileList();
    // 强制刷新预览组件
    _loadPreviewStreamUrl(forceRefresh: true);
    // 重新初始化方向状态
    _initializeOrientationLock();
    // 重新连接WebSocket通知流
    _connectToWebSocketNotifications();
  }
  
  /// 是否已连接（connected 或 registered 状态）
  bool get _isConnected => 
      _connectionState == ws.ConnectionState.connected ||
      _connectionState == ws.ConnectionState.registered;
  
  /// 是否正在重连
  bool get _isReconnecting => _connectionState == ws.ConnectionState.reconnecting;
  
  /// 手动触发重连
  Future<void> _manualReconnect() async {
    _logger.log('手动触发重连', tag: 'CONNECTION');
    try {
      // 调用 ApiService 的连接方法，它会触发 WebSocketConnection 的重连
      await widget.apiService.connectWebSocket();
      if (mounted) {
        _showSuccess('重连成功');
      }
    } catch (e) {
      if (mounted) {
        final error = ConnectionError.fromException(e);
        _showError(error.getUserFriendlyMessage());
      }
    }
  }

  /// 加载预览流URL（包含客户端版本号）
  /// [forceRefresh] 为 true 时强制刷新预览组件（用于重连后）
  Future<void> _loadPreviewStreamUrl({bool forceRefresh = false}) async {
    try {
      final url = await widget.apiService.getPreviewStreamUrl();
      if (mounted) {
        setState(() {
          _previewStreamUrl = url;
          if (forceRefresh) {
            _previewInitKey++; // 强制重建预览组件
            _logger.log('强制刷新预览组件，新key: $_previewInitKey', tag: 'PREVIEW');
          }
        });
      }
    } catch (e) {
      _logger.logError('获取预览流URL失败', error: e);
      // 即使失败也设置一个基本URL（向后兼容）
      if (mounted) {
        setState(() {
          _previewStreamUrl = '${widget.apiService.baseUrl}/preview/stream';
          if (forceRefresh) {
            _previewInitKey++; // 强制重建预览组件
            _logger.log('强制刷新预览组件（fallback URL），新key: $_previewInitKey', tag: 'PREVIEW');
          }
        });
      }
    }
  }

  /// 初始化方向锁定状态
  Future<void> _initializeOrientationLock() async {
    if (!mounted) return;

    try {
      // 先从本地存储读取保存的偏好设置
      final savedPrefs = await _orientationPrefs.getAllPreferences();
      final savedOrientationLocked = savedPrefs['orientationLocked'] as bool;
      final savedLockedRotationAngle = savedPrefs['lockedRotationAngle'] as int;

      _logger.log(
          '从本地存储读取方向偏好: 锁定=$savedOrientationLocked, 锁定角度=$savedLockedRotationAngle°',
          tag: 'ORIENTATION');

      // 先使用本地保存的值设置本地状态
      if (mounted) {
        setState(() {
          _orientationLocked = savedOrientationLocked;
          _lockedRotationAngle = savedLockedRotationAngle;
        });
      }

      // 从服务器获取方向状态（获取传感器方向和设备方向）
      final result = await widget.apiService.getSettingsStatus();
      if (!mounted) return;

      if (result['success'] == true && result['status'] != null) {
        final status = result['status'] as Map<String, dynamic>;
        
        // 统一处理预览尺寸更新
        if (status['previewSize'] != null) {
          final previewSize = status['previewSize'] as Map<String, dynamic>?;
          _updatePreviewSize(previewSize);
        }
        
        final orientation = status['orientation'] as Map<String, dynamic>?;

        if (orientation != null) {
          final currentDeviceOrientation =
              orientation['currentDeviceOrientation'] as int? ?? 0;
          final sensorOrientation =
              orientation['sensorOrientation'] as int? ?? 0;

          _logger.log(
              '从服务器获取方向状态: 设备方向=$currentDeviceOrientation, 传感器方向=$sensorOrientation',
              tag: 'ORIENTATION');

          // 更新传感器方向和设备方向
          if (mounted) {
            setState(() {
              _sensorOrientation = sensorOrientation;
            });
          }
          _deviceOrientationNotifier.value = currentDeviceOrientation;

          // 将本地保存的偏好设置同步到服务器
          try {
            await widget.apiService.setOrientationLock(savedOrientationLocked);
            if (savedOrientationLocked) {
              await widget.apiService
                  .setLockedRotationAngle(savedLockedRotationAngle);
              _logger.log(
                  '已同步本地偏好设置到服务器: 锁定=$savedOrientationLocked, 锁定角度=$savedLockedRotationAngle°',
                  tag: 'ORIENTATION');
            }
          } catch (e, stackTrace) {
            _logger.logError('同步偏好设置到服务器失败', error: e, stackTrace: stackTrace);
            // 继续执行，不中断初始化流程
          }
        } else {
          // 如果没有方向信息，使用默认值
          _logger.log('服务器未返回方向信息，使用本地保存的偏好设置', tag: 'ORIENTATION');
        }
      } else {
        _logger.log('获取服务器状态失败，使用本地保存的偏好设置', tag: 'ORIENTATION');
      }

      // 更新客户端预览旋转角度
      if (mounted) {
        _updatePreviewRotation();
        // 初始化预览（获取第一帧并转置）
        _initializePreview();
      }
    } catch (e, stackTrace) {
      _logger.logError('初始化方向锁定状态失败', error: e, stackTrace: stackTrace);
      // 出错时使用默认值
      if (mounted) {
        _updatePreviewRotation();
        // 即使出错也尝试初始化预览
        _initializePreview();
      }
    }
  }

  /// 计算并更新转置后的预览尺寸
  /// 根据原始尺寸和旋转角度计算转置后的尺寸
  void _updateTransformedPreviewSize() {
    if (!mounted) return;

    final rotationAngle = _rotationAngleNotifier.value;
    final originalWidth = _previewSizeNotifier.value['width'] ?? 640;
    final originalHeight = _previewSizeNotifier.value['height'] ?? 480;

    int transformedWidth = originalWidth;
    int transformedHeight = originalHeight;
    if (rotationAngle == 90 || rotationAngle == 270) {
      transformedWidth = originalHeight;
      transformedHeight = originalWidth;
    }

    final currentTransformed = _transformedPreviewSizeNotifier.value;
    if (currentTransformed['width'] != transformedWidth ||
        currentTransformed['height'] != transformedHeight) {
      _logger.log(
          '预览转置尺寸确定: ${originalWidth}x${originalHeight} -> ${transformedWidth}x${transformedHeight} (旋转角度=$rotationAngle°)',
          tag: 'PREVIEW');

      _transformedPreviewSizeNotifier.value = {
        'width': transformedWidth,
        'height': transformedHeight,
      };
      _previewInitKey++; // 触发预览组件重建
      _previewInitialized = true;
    }
  }

  /// 初始化预览（使用服务器返回的预览尺寸，不需要获取第一帧）
  void _initializePreview() {
    if (!mounted || _previewStreamUrl == null) return;

    _logger.log('开始初始化预览，使用服务器返回的预览尺寸', tag: 'PREVIEW');
    _updateTransformedPreviewSize();
    _logger.log('预览初始化完成', tag: 'PREVIEW');
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _webSocketSubscription?.cancel();
    _deviceOrientationNotifier.dispose();
    _rotationAngleNotifier.dispose();
    _previewSizeNotifier.dispose();
    _transformedPreviewSizeNotifier.dispose();
    super.dispose();
  }

  /// 启动WebSocket连接（监听server的新文件通知）
  void _startFileListRefreshTimer() {
    _logger.log('准备启动WebSocket通知监听', tag: 'WEBSOCKET');
    _connectToWebSocketNotifications();
  }

  /// 连接到WebSocket通知流（监听服务器推送的通知）
  Future<void> _connectToWebSocketNotifications() async {
    if (!mounted || !_isConnected) return;

    try {
      // 确保ApiService的WebSocket已连接
      await widget.apiService.connectWebSocket();

      // 监听通知消息
      final notificationStream = widget.apiService.webSocketNotifications;
      if (notificationStream == null) {
        _logger.log('WebSocket通知流不可用', tag: 'WEBSOCKET');
        return;
      }

      // 取消之前的订阅
      _webSocketSubscription?.cancel();

      _webSocketSubscription = notificationStream.listen(
        (notification) {
          _logger.log('收到WebSocket通知原始数据: $notification', tag: 'WEBSOCKET');
          _logger.log('当前连接状态: mounted=$mounted, _isConnected=$_isConnected',
              tag: 'WEBSOCKET');

          if (!mounted || !_isConnected) {
            _logger.log('跳过通知处理: mounted=$mounted, _isConnected=$_isConnected',
                tag: 'WEBSOCKET');
            return;
          }

          try {
            final event = notification['event'] as String?;
            final data = notification['data'] as Map<String, dynamic>?;

            _logger.log('收到WebSocket通知: event=$event', tag: 'WEBSOCKET');

            // 处理新文件通知
            if (event == 'new_files' && data != null) {
              _logger.log('收到新文件通知，直接使用通知中的文件信息', tag: 'WEBSOCKET');
              // 收到新文件通知，直接使用通知中的文件信息
              _handleNewFilesNotification(data);
            } else if (event == 'orientation_changed' && data != null) {
              // 处理设备方向变化通知
              final orientation = data['orientation'] as int?;
              _logger.log(
                  '处理方向变化通知: orientation=$orientation, _orientationLocked=$_orientationLocked',
                  tag: 'ORIENTATION');
              if (orientation != null) {
                _logger.log('收到设备方向变化通知: $orientation 度', tag: 'ORIENTATION');
                if (mounted) {
                  _deviceOrientationNotifier.value = orientation;
                  // 只有在解锁状态下才更新预览旋转角度
                  // 锁定状态下旋转角度由锁定角度决定，不受设备方向影响
                  if (!_orientationLocked) {
                    _logger.log('方向已解锁，更新预览旋转角度并重新初始化预览', tag: 'ORIENTATION');
                    _updatePreviewRotation(); // 这会触发重新初始化
                  } else {
                    _logger.log('方向已锁定，跳过更新预览旋转角度', tag: 'ORIENTATION');
                  }
                }
              }
            } else if (event == 'version_incompatible' || 
                       event == 'server_version_incompatible' ||
                       event == 'connection_failed') {
              // 版本不兼容或连接失败通知 - 由 WebSocketConnection 处理，这里只显示错误
              final messageData = data as Map<String, dynamic>?;
              final message = messageData?['message'] as String? ?? '连接失败';
              final minRequiredVersion = messageData?['minRequiredVersion'] as String?;
              
              _logger.log('连接失败通知: $message', tag: 'VERSION_COMPAT');
              
              if (mounted) {
                String errorMessage = message;
                if (minRequiredVersion != null) {
                  errorMessage = '$message\n\n要求最小版本: $minRequiredVersion';
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 8),
                  ),
                );
              }
            } else if (event == 'connected') {
              _logger.log('WebSocket连接确认', tag: 'WEBSOCKET');
              // 统一处理预览尺寸更新
              if (data != null && data['previewSize'] != null) {
                final previewSize = data['previewSize'] as Map<String, dynamic>?;
                _updatePreviewSize(previewSize);
              }
            }
          } catch (e) {
            _logger.logError('处理WebSocket通知失败', error: e);
          }
        },
        onError: (error) {
          _logger.logError('WebSocket通知流错误', error: error);
          // WebSocketConnection 会自动处理重连，这里不需要手动重连
        },
        cancelOnError: false,
      );
      
      _logger.log('WebSocket通知流连接成功', tag: 'WEBSOCKET');
    } catch (e, stackTrace) {
      _logger.logError('连接WebSocket通知流失败', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _refreshFileList() async {
    try {
      final result = await widget.apiService.getFileList();
      if (result['success'] && mounted) {
        final pictures = result['pictures'] as List<FileInfo>;
        final videos = result['videos'] as List<FileInfo>;

        // 检查所有文件的下载状态
        await _checkDownloadStatus([...pictures, ...videos]);

        setState(() {
          _pictures = pictures;
          _videos = videos;
        });
      }
    } catch (e) {
      _showError('刷新文件列表失败: $e');
    }
  }

  /// 批量检查文件下载状态
  Future<void> _checkDownloadStatus(List<FileInfo> files) async {
    final downloadDir = await _downloadSettings.getDownloadPath();
    for (var file in files) {
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      _downloadedStatusCache[file.name] = await localFile.exists();
    }
  }

  Future<void> _takePicture() async {
    setState(() {
      _isOperating = true;
    });

    try {
      final result = await widget.apiService.capture();
      if (result['success']) {
        _showSuccess('拍照成功');
        _logger.log('拍照成功，等待WebSocket通知更新文件列表', tag: 'CAMERA');
        // 不再手动刷新，依赖WebSocket通知来更新文件列表
        // 文件列表更新和自动下载会在 _handleNewFilesNotification 中处理
      } else {
        _showError('拍照失败: ${result['error']}');
      }
    } catch (e) {
      _showError('拍照失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  /// 增量更新文件列表（只获取新增/修改的文件）
  /// 处理新文件通知（直接使用通知中的文件信息）
  Future<void> _handleNewFilesNotification(Map<String, dynamic> data) async {
    try {
      _logger.log('收到新文件通知，开始处理', tag: 'FILE_NOTIFICATION');
      final fileType = data['fileType'] as String?;
      final filesData = data['files'] as List<dynamic>?;

      _logger.log('文件类型: $fileType, 文件数量: ${filesData?.length ?? 0}',
          tag: 'FILE_NOTIFICATION');

      if (filesData == null || filesData.isEmpty) {
        _logger.log('没有文件信息，回退到增量刷新', tag: 'FILE_NOTIFICATION');
        await _incrementalRefreshFileList();
        return;
      }

      // 解析文件信息
      final List<FileInfo> newFiles = [];
      for (var fileJson in filesData) {
        try {
          final fileInfo = FileInfo.fromJson(fileJson as Map<String, dynamic>);
          newFiles.add(fileInfo);
          _logger.log('解析文件成功: ${fileInfo.name}', tag: 'FILE_NOTIFICATION');
        } catch (e) {
          _logger.logError('解析文件信息失败', error: e);
        }
      }

      if (newFiles.isEmpty) {
        _logger.log('解析后没有有效文件，跳过更新', tag: 'FILE_NOTIFICATION');
        return;
      }

      _logger.log('成功解析 ${newFiles.length} 个文件，准备更新UI',
          tag: 'FILE_NOTIFICATION');

      // 检查新文件的下载状态
      await _checkDownloadStatus(newFiles);

      // 合并新文件到现有列表（去重，按修改时间排序）
      final existingFileNames = <String>{};
      for (var file in [..._pictures, ..._videos]) {
        existingFileNames.add(file.name);
      }

      final updatedPictures = <FileInfo>[..._pictures];
      final updatedVideos = <FileInfo>[..._videos];

      for (var file in newFiles) {
        if (!existingFileNames.contains(file.name)) {
          // 根据文件类型添加到对应列表
          if (fileType == 'image' || file.isImage) {
            updatedPictures.add(file);
          } else if (fileType == 'video' || file.isVideo) {
            updatedVideos.add(file);
          }
          existingFileNames.add(file.name);
        } else {
          // 更新已存在的文件
          if (fileType == 'image' || file.isImage) {
            final index =
                updatedPictures.indexWhere((f) => f.name == file.name);
            if (index >= 0) {
              updatedPictures[index] = file;
            }
          } else if (fileType == 'video' || file.isVideo) {
            final index = updatedVideos.indexWhere((f) => f.name == file.name);
            if (index >= 0) {
              updatedVideos[index] = file;
            }
          }
        }
      }

      // 按修改时间排序
      updatedPictures.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
      updatedVideos.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));

      _logger.log(
          '更新文件列表: 照片 ${updatedPictures.length} 张, 视频 ${updatedVideos.length} 个',
          tag: 'FILE_NOTIFICATION');

      if (mounted) {
        setState(() {
          _pictures = updatedPictures;
          _videos = updatedVideos;
        });
        _logger.log('UI已更新', tag: 'FILE_NOTIFICATION');

        // 自动下载最新照片/视频
        if (fileType == 'image' && updatedPictures.isNotEmpty) {
          final latestPicture = updatedPictures.first;
          await _autoDownloadPicture(latestPicture);
        } else if (fileType == 'video' && updatedVideos.isNotEmpty) {
          final latestVideo = updatedVideos.first;
          await _autoDownloadVideo(latestVideo);
        }
      }
    } catch (e) {
      _logger.logError('处理新文件通知失败', error: e);
      // 如果处理失败，回退到增量刷新
      await _incrementalRefreshFileList();
    }
  }

  Future<void> _incrementalRefreshFileList() async {
    try {
      // 计算最后更新时间（使用最新文件的修改时间，减去1秒以确保能获取到新文件）
      int? since;
      if (_pictures.isNotEmpty || _videos.isNotEmpty) {
        final allFiles = [..._pictures, ..._videos];
        allFiles.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
        // 减去1秒，确保能获取到刚刚创建的文件（即使时间戳相同）
        since = allFiles.first.modifiedTime.millisecondsSinceEpoch - 1000;
      }

      final result = await widget.apiService.getFileList(since: since);

      if (result['success'] && mounted) {
        final newPictures = result['pictures'] as List<FileInfo>;
        final newVideos = result['videos'] as List<FileInfo>;

        if (newPictures.isEmpty && newVideos.isEmpty) {
          // 没有新文件，不需要更新
          return;
        }

        // 检查新文件的下载状态
        await _checkDownloadStatus([...newPictures, ...newVideos]);

        // 合并新文件到现有列表（去重，按修改时间排序）
        final existingFileNames = <String>{};
        for (var file in [..._pictures, ..._videos]) {
          existingFileNames.add(file.name);
        }

        final updatedPictures = <FileInfo>[..._pictures];
        final updatedVideos = <FileInfo>[..._videos];

        for (var file in newPictures) {
          if (!existingFileNames.contains(file.name)) {
            updatedPictures.add(file);
            existingFileNames.add(file.name);
          } else {
            // 更新已存在的文件
            final index =
                updatedPictures.indexWhere((f) => f.name == file.name);
            if (index >= 0) {
              updatedPictures[index] = file;
            }
          }
        }

        for (var file in newVideos) {
          if (!existingFileNames.contains(file.name)) {
            updatedVideos.add(file);
            existingFileNames.add(file.name);
          } else {
            // 更新已存在的文件
            final index = updatedVideos.indexWhere((f) => f.name == file.name);
            if (index >= 0) {
              updatedVideos[index] = file;
            }
          }
        }

        // 按修改时间排序
        updatedPictures
            .sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
        updatedVideos.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));

        setState(() {
          _pictures = updatedPictures;
          _videos = updatedVideos;
        });
      }
    } catch (e) {
      // 增量更新失败不影响UI，只记录错误
      _logger.logError('增量更新文件列表失败', error: e);
    }
  }

  Future<void> _autoDownloadPicture(FileInfo file) async {
    try {
      // 检查是否已经在下载中或已完成
      final existingTask = await _downloadManager.findTaskByFileName(file.name);

      if (existingTask != null) {
        if (existingTask.status == DownloadStatus.downloading ||
            existingTask.status == DownloadStatus.pending) {
          // 已经在下载中
          return;
        }

        if (existingTask.status == DownloadStatus.completed) {
          // 已经下载完成
          if (mounted) {
            _showDownloadSuccess(file.name, existingTask.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
          return;
        }
      }

      final taskId = await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );

      // 取消之前的订阅
      _downloadSubscription?.cancel();

      // 监听下载完成（只监听一次）
      _downloadSubscription = _downloadManager.tasksStream.listen((tasks) {
        final task = tasks.firstWhere(
          (t) => t.id == taskId,
          orElse: () => tasks.first,
        );

        if (task.status == DownloadStatus.completed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showDownloadSuccess(file.name, task.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
        } else if (task.status == DownloadStatus.failed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showError('下载失败: ${file.name}');
          }
        }
      });
    } catch (e) {
      final logger = ClientLoggerService();
      logger.logError('自动下载失败', error: e);
    }
  }

  Future<void> _showDownloadSuccess(String fileName, String filePath) async {
    final downloadDir = await _downloadSettings.getDownloadPath();

    // 自动导入到媒体库
    await _importToMediaLibrary(filePath, fileName);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已保存: $fileName'),
            const Text(
              '已自动导入到媒体库',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '打开文件夹',
          onPressed: () {
            _openFolder(downloadDir);
          },
        ),
      ),
    );
  }

  /// 将下载的文件导入到媒体库
  Future<void> _importToMediaLibrary(String filePath, String fileName) async {
    try {
      final libraryService = MediaLibraryService.instance;
      // 确保媒体库服务已初始化
      await libraryService.init();
      
      // 导入文件，使用 "phone_camera" 作为来源标识
      // copyFile: false 表示不复制文件，只建立索引（文件已在下载目录）
      final result = await libraryService.importFile(
        filePath,
        sourceId: 'phone_camera',
        copyFile: false,
      );
      
      if (result.success && result.mediaItem != null) {
        _logger.log('文件已导入媒体库: $fileName, id=${result.mediaItem!.id}', tag: 'MEDIA_IMPORT');
      } else {
        _logger.log('文件导入媒体库失败: $fileName, error=${result.error}', tag: 'MEDIA_IMPORT');
      }
    } catch (e) {
      _logger.logError('导入媒体库失败: $fileName', error: e);
    }
  }

  Future<void> _openFolder(String folderPath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [folderPath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [folderPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [folderPath]);
      }
    } catch (e) {
      _showError('打开文件夹失败: $e');
    }
  }

  Future<void> _toggleRecording() async {
    setState(() {
      _isOperating = true;
    });

    try {
      final result = _isRecording
          ? await widget.apiService.stopRecording()
          : await widget.apiService.startRecording();

      if (result['success']) {
        final wasRecording = _isRecording;
        setState(() {
          _isRecording = !_isRecording;
        });
        _showSuccess(_isRecording ? '录像已开始' : '录像已停止');

        if (!wasRecording && _isRecording) {
          // 录像已开始
        } else if (wasRecording && !_isRecording) {
          // 录像已停止，等待WebSocket通知更新文件列表
          _logger.log('录像已停止，等待WebSocket通知更新文件列表', tag: 'CAMERA');
          // 不再手动刷新，依赖WebSocket通知来更新文件列表
          // 文件列表更新和自动下载会在 _handleNewFilesNotification 中处理
        }
      } else {
        _showError('操作失败: ${result['error']}');
      }
    } catch (e) {
      _showError('操作失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  Future<void> _autoDownloadVideo(FileInfo file) async {
    try {
      // 检查是否已经在下载中或已完成
      final existingTask = await _downloadManager.findTaskByFileName(file.name);

      if (existingTask != null) {
        if (existingTask.status == DownloadStatus.downloading ||
            existingTask.status == DownloadStatus.pending) {
          // 已经在下载中
          return;
        }

        if (existingTask.status == DownloadStatus.completed) {
          // 已经下载完成
          if (mounted) {
            _showDownloadSuccess(file.name, existingTask.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
          return;
        }
      }

      final taskId = await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );

      // 取消之前的订阅
      _downloadSubscription?.cancel();

      // 监听下载完成（只监听一次）
      _downloadSubscription = _downloadManager.tasksStream.listen((tasks) {
        final task = tasks.firstWhere(
          (t) => t.id == taskId,
          orElse: () => tasks.first,
        );

        if (task.status == DownloadStatus.completed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showDownloadSuccess(file.name, task.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
        } else if (task.status == DownloadStatus.failed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showError('下载失败: ${file.name}');
          }
        }
      });
    } catch (e) {
      final logger = ClientLoggerService();
      logger.logError('自动下载视频失败', error: e);
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 更新预览旋转角度（客户端处理旋转）
  /// 预览旋转角度必须与拍照方向一致，确保预览和拍摄的画面状态一致
  void _updatePreviewRotation() {
    if (!mounted) return;

    try {
      // 客户端根据锁定状态和方向计算旋转角度，与拍照方向一致
      // 锁定状态：sensorOrientation + 90 + lockedRotationAngle（与拍照逻辑一致）
      // 解锁状态：sensorOrientation + currentDeviceOrientation（与拍照逻辑一致）
      final oldRotationAngle = _rotationAngleNotifier.value;
      final rotationAngle = _orientationLocked
          ? (_sensorOrientation + 90 + _lockedRotationAngle) % 360
          : (_sensorOrientation + _deviceOrientationNotifier.value) % 360;
      _rotationAngleNotifier.value = rotationAngle;
      _logger.log(
          '更新预览旋转角度: ${_orientationLocked ? "锁定" : "解锁"}, 角度=$rotationAngle° (传感器=$_sensorOrientation°, ${_orientationLocked ? "锁定角度=$_lockedRotationAngle°" : "设备方向=${_deviceOrientationNotifier.value}°"})',
          tag: 'PREVIEW');

      // 旋转角度改变后，自动更新转置后的尺寸
      if (oldRotationAngle != rotationAngle) {
        _updateTransformedPreviewSize();
      }
    } catch (e, stackTrace) {
      _logger.logError('更新预览旋转角度失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 旋转预览（锁定状态下）
  Future<void> _rotatePreview() async {
    if (!mounted) return;

    final newAngle = (_lockedRotationAngle + 90) % 360;
    try {
      // 发送旋转角度到服务器（用于拍照方向）
      final result = await widget.apiService.setLockedRotationAngle(newAngle);
      if (!mounted) return;

      if (result['success'] == true) {
        if (mounted) {
          setState(() => _lockedRotationAngle = newAngle);
        }
        // 保存到本地存储
        await _orientationPrefs.saveLockedRotationAngle(newAngle);
        // 更新客户端预览旋转角度（会触发重新初始化）
        if (mounted) {
          _updatePreviewRotation();
          _showSuccess('预览已旋转到 ${newAngle}°');
        }
      } else {
        if (mounted) {
          _showError('设置旋转角度失败: ${result['error']}');
        }
      }
    } catch (e, stackTrace) {
      _logger.logError('旋转预览失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        _showError('设置旋转角度失败: $e');
      }
    }
  }

  /// 切换方向锁定状态
  Future<void> _toggleOrientationLock() async {
    if (!mounted) return;

    final newLockState = !_orientationLocked;
    try {
      final result = await widget.apiService.setOrientationLock(newLockState);
      if (!mounted) return;

      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            _orientationLocked = newLockState;
          });
        }
        // 保存到本地存储
        await _orientationPrefs.saveOrientationLocked(newLockState);
        // 如果切换到锁定状态，确保服务器使用当前的锁定角度
        if (newLockState) {
          await widget.apiService.setLockedRotationAngle(_lockedRotationAngle);
        }
        // 更新客户端预览旋转角度（会触发重新初始化）
        if (mounted) {
          _updatePreviewRotation();
          _showSuccess(newLockState ? '方向已锁定' : '方向已解锁');
        }
      } else {
        if (mounted) {
          _showError('设置方向锁定失败: ${result['error']}');
        }
      }
    } catch (e, stackTrace) {
      _logger.logError('切换方向锁定状态失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        _showError('设置方向锁定失败: $e');
      }
    }
  }

  void _navigateToSettings() async {
    // 直接打开全屏设置选择页面
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsSelectionScreen(
          apiService: widget.apiService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final totalHeight = constraints.maxHeight;
                
                // 记录窗口尺寸
                _logger.log(
                    '预览窗口尺寸: ${totalWidth.toInt()}x${totalHeight.toInt()}',
                    tag: 'PREVIEW');

                // 简化布局：全屏预览 + 底部控制栏
                return Column(
                  children: [
                    // 预览区域（占据大部分空间）
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              // 预览窗口
                              Positioned.fill(
                                child: ValueListenableBuilder<Map<String, int>>(
                                  valueListenable: _previewSizeNotifier,
                                  builder: (context, previewSize, _) {
                                    return ValueListenableBuilder<int>(
                                      valueListenable: _rotationAngleNotifier,
                                      builder: (context, rotationAngle, _) {
                                        if (_previewStreamUrl == null || !_previewInitialized) {
                                          return const Center(
                                            child: CircularProgressIndicator(),
                                          );
                                        }

                                        final originalWidth = previewSize['width'] ?? 640;
                                        final originalHeight = previewSize['height'] ?? 480;

                                        return TransformedPreviewWidget(
                                          key: ValueKey('transformed_preview_$_previewInitKey'),
                                          streamUrl: _previewStreamUrl!,
                                          rotationAngle: rotationAngle,
                                          originalWidth: originalWidth,
                                          originalHeight: originalHeight,
                                          onSizeDetermined: (width, height) {
                                            if (mounted) {
                                              _transformedPreviewSizeNotifier.value = {
                                                'width': width,
                                                'height': height,
                                              };
                                            }
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              // 录像中指示器
                              if (_isRecording)
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.fiber_manual_record,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          '录像中',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // 重连状态指示器
                              if (!_isConnected || _isReconnecting)
                                Positioned(
                                  top: 16,
                                  left: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isReconnecting ? Colors.orange : Colors.red,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isReconnecting)
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        else
                                          const Icon(
                                            Icons.link_off,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _isReconnecting 
                                              ? '重连中 ($_reconnectAttempts/20)' 
                                              : '已断开',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (!_isConnected && !_isReconnecting) ...[
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: _manualReconnect,
                                            child: const Icon(
                                              Icons.refresh,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 底部控制栏
                    Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 设置按钮
                          IconButton(
                            icon: const Icon(Icons.settings),
                            color: Colors.white,
                            onPressed: _navigateToSettings,
                            tooltip: '相机设置',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 下载管理按钮
                          IconButton(
                            icon: const Icon(Icons.download),
                            color: Colors.white,
                            onPressed: _navigateToDownloadManager,
                            tooltip: '下载管理',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 旋转按钮（只在锁定状态时显示）
                          if (_orientationLocked)
                            IconButton(
                              icon: const Icon(Icons.rotate_90_degrees_cw),
                              color: Colors.blue,
                              onPressed: _rotatePreview,
                              tooltip: '旋转预览（当前: ${_lockedRotationAngle}°）',
                              style: IconButton.styleFrom(
                                  backgroundColor: Colors.blue.withOpacity(0.2)),
                            ),
                          // 方向锁定按钮
                          IconButton(
                            icon: Icon(_orientationLocked
                                ? Icons.lock
                                : Icons.lock_open),
                            color: _orientationLocked
                                ? Colors.orange
                                : Colors.grey,
                            onPressed: _toggleOrientationLock,
                            tooltip: _orientationLocked ? '方向已锁定' : '方向已解锁',
                            style: IconButton.styleFrom(
                              backgroundColor: _orientationLocked
                                  ? Colors.orange.withOpacity(0.2)
                                  : Colors.transparent,
                            ),
                          ),
                          const SizedBox(width: 24),
                          // 拍照按钮（大按钮）
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: ElevatedButton(
                              onPressed: (_isOperating || _isRecording)
                                  ? null
                                  : _takePicture,
                              style: ElevatedButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(16),
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                              child: const Icon(Icons.camera_alt, size: 32),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // 录像按钮
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: _isOperating ? null : _toggleRecording,
                              style: ElevatedButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(12),
                                backgroundColor: _isRecording ? Colors.red : Colors.red[300],
                              ),
                              child: Icon(
                                _isRecording ? Icons.stop : Icons.fiber_manual_record,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // 媒体库入口
                          IconButton(
                            icon: const Icon(Icons.photo_library),
                            color: Colors.white,
                            onPressed: _navigateToMediaLibrary,
                            tooltip: '媒体库',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 导航到媒体库
  void _navigateToMediaLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LibraryScreen(),
      ),
    );
  }

  /// 导航到下载管理
  void _navigateToDownloadManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DownloadManagerScreen(
          apiService: widget.apiService,
        ),
      ),
    );
  }
}
