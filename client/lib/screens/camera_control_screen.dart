import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../models/file_info.dart';
import '../models/download_task.dart';
import '../widgets/mjpeg_stream_widget.dart';
import '../services/orientation_preferences_service.dart';
import 'settings_screen.dart';
import 'advanced_camera_settings_screen.dart';
import 'settings_selection_screen.dart';
import 'file_manager_screen.dart';
import 'client_settings_screen.dart';
import 'device_connection_screen.dart';
import 'camera_capabilities_screen.dart';
import 'package:path/path.dart' as path;
import '../services/logger_service.dart';
import '../services/download_settings_service.dart';
import '../services/connection_settings_service.dart';

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

  // 连接状态管理
  bool _isConnected = true;
  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  Timer? _connectionCheckTimer;
  StreamSubscription? _webSocketSubscription; // WebSocket通知消息订阅
  final ClientLoggerService _logger = ClientLoggerService();

  // 左右布局比例（0.0-1.0，表示左侧占比）
  double _leftPanelRatio = 0.3; // 默认左侧30%

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

  // 当前旋转角度（0-360度），用于客户端旋转预览流
  final ValueNotifier<int> _rotationAngleNotifier = ValueNotifier<int>(0);

  // 方向偏好设置服务
  final OrientationPreferencesService _orientationPrefs =
      OrientationPreferencesService();

  @override
  void initState() {
    super.initState();
    _downloadManager = DownloadManager(baseUrl: widget.apiService.baseUrl);
    _downloadManager.initialize();
    _refreshFileList();
    _startConnectionCheck();
    _startFileListRefreshTimer(); // 启动WebSocket连接并监听通知
    // 连接WebSocket（用于API调用）
    widget.apiService.connectWebSocket();
    // 初始化方向锁定状态（默认锁定）
    _initializeOrientationLock();
  }

  /// 初始化方向锁定状态
  Future<void> _initializeOrientationLock() async {
    try {
      // 先从本地存储读取保存的偏好设置
      final savedPrefs = await _orientationPrefs.getAllPreferences();
      final savedOrientationLocked = savedPrefs['orientationLocked'] as bool;
      final savedLockedRotationAngle = savedPrefs['lockedRotationAngle'] as int;

      _logger.log(
          '从本地存储读取方向偏好: 锁定=$savedOrientationLocked, 锁定角度=$savedLockedRotationAngle°',
          tag: 'ORIENTATION');

      // 先使用本地保存的值设置本地状态
      setState(() {
        _orientationLocked = savedOrientationLocked;
        _lockedRotationAngle = savedLockedRotationAngle;
      });

      // 从服务器获取方向状态（获取传感器方向和设备方向）
      final result = await widget.apiService.getSettingsStatus();
      if (result['success'] == true && result['status'] != null) {
        final status = result['status'] as Map<String, dynamic>;
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
          setState(() {
            _sensorOrientation = sensorOrientation;
          });
          _deviceOrientationNotifier.value = currentDeviceOrientation;

          // 将本地保存的偏好设置同步到服务器
          await widget.apiService.setOrientationLock(savedOrientationLocked);
          if (savedOrientationLocked) {
            await widget.apiService
                .setLockedRotationAngle(savedLockedRotationAngle);
            _logger.log(
                '已同步本地偏好设置到服务器: 锁定=$savedOrientationLocked, 锁定角度=$savedLockedRotationAngle°',
                tag: 'ORIENTATION');
          }
        } else {
          // 如果没有方向信息，使用默认值
          _logger.log('服务器未返回方向信息，使用本地保存的偏好设置', tag: 'ORIENTATION');
        }
      } else {
        _logger.log('获取服务器状态失败，使用本地保存的偏好设置', tag: 'ORIENTATION');
      }

      // 更新客户端预览旋转角度
      _updatePreviewRotation();
    } catch (e, stackTrace) {
      _logger.logError('初始化方向锁定状态失败', error: e, stackTrace: stackTrace);
      // 出错时使用默认值
      _updatePreviewRotation();
    }
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _reconnectTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _webSocketSubscription?.cancel();
    _deviceOrientationNotifier.dispose();
    _rotationAngleNotifier.dispose();
    _previewSizeNotifier.dispose();
    super.dispose();
  }

  /// 启动WebSocket连接（监听server的新文件通知）
  void _startFileListRefreshTimer() {
    _logger.log('准备启动WebSocket通知监听', tag: 'WEBSOCKET');
    _connectToWebSocketNotifications();
  }

  /// 连接到WebSocket通知流（监听服务器推送的通知）
  void _connectToWebSocketNotifications() async {
    try {
      // 确保ApiService的WebSocket已连接
      await widget.apiService.connectWebSocket();

      // 监听通知消息
      final notificationStream = widget.apiService.webSocketNotifications;
      if (notificationStream != null) {
        _webSocketSubscription = notificationStream.listen(
          (notification) {
            if (!mounted || !_isConnected) {
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
                if (orientation != null) {
                  _logger.log('收到设备方向变化通知: $orientation 度', tag: 'ORIENTATION');
                  if (mounted) {
                    _deviceOrientationNotifier.value = orientation;
                    // 更新客户端预览旋转角度
                    _updatePreviewRotation();
                  }
                }
              } else if (event == 'connected') {
                _logger.log('WebSocket连接确认', tag: 'WEBSOCKET');
                // 获取预览尺寸
                if (data != null && data['previewSize'] != null) {
                  final previewSize =
                      data['previewSize'] as Map<String, dynamic>?;
                  if (previewSize != null) {
                    final width = previewSize['width'] as int? ?? 640;
                    final height = previewSize['height'] as int? ?? 480;
                    if (mounted) {
                      _previewSizeNotifier.value = {
                        'width': width,
                        'height': height
                      };
                      _logger.log('收到服务器预览尺寸: ${width}x${height}',
                          tag: 'PREVIEW');
                    }
                  }
                }
              }
            } catch (e) {
              _logger.logError('处理WebSocket通知失败', error: e);
            }
          },
          onError: (error) {
            _logger.logError('WebSocket通知流错误', error: error);
            // 连接失败，5秒后重试
            if (mounted && _isConnected) {
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted && _isConnected) {
                  _connectToWebSocketNotifications();
                }
              });
            }
          },
          cancelOnError: false,
        );
      }
    } catch (e, stackTrace) {
      _logger.logError('连接WebSocket通知流失败', error: e, stackTrace: stackTrace);
      // 连接失败，5秒后重试
      if (mounted && _isConnected) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _isConnected) {
            _connectToWebSocketNotifications();
          }
        });
      }
    }
  }

  // 开始连接检查
  void _startConnectionCheck() {
    _connectionCheckTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final pingSuccess = await widget.apiService.ping();
        if (!mounted) return;

        // 只在连接状态实际变化时才调用 setState
        if (!pingSuccess && _isConnected) {
          // 连接断开
          setState(() {
            _isConnected = false;
          });
          _logger.log('检测到连接断开', tag: 'CONNECTION');
          _startReconnect();
        } else if (pingSuccess && !_isConnected) {
          // 连接恢复
          setState(() {
            _isConnected = true;
            _isReconnecting = false;
          });
          _logger.log('连接已恢复', tag: 'CONNECTION');
          _refreshFileList();
        }
        // 如果连接状态没有变化（pingSuccess == _isConnected），不调用 setState
      } catch (e) {
        if (mounted && _isConnected) {
          setState(() {
            _isConnected = false;
          });
          _logger.logError('连接检查失败', error: e);
          _startReconnect();
        }
      }
    });
  }

  // 开始重连
  void _startReconnect() {
    if (_isReconnecting) {
      _logger.log('已在重连中，跳过', tag: 'CONNECTION');
      return;
    }

    _logger.log('开始重连流程', tag: 'CONNECTION');
    setState(() {
      _isReconnecting = true;
    });

    _reconnectTimer?.cancel();
    int reconnectAttempts = 0;
    const maxReconnectAttempts = 20; // 最多尝试20次（约1分钟）

    _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      reconnectAttempts++;
      if (reconnectAttempts > maxReconnectAttempts) {
        _logger.log('达到最大重连次数，停止重连', tag: 'CONNECTION');
        timer.cancel();
        _reconnectTimer = null;
        if (mounted) {
          setState(() {
            _isReconnecting = false;
          });
        }
        return;
      }

      try {
        _logger.log('尝试重连... (第$reconnectAttempts次)', tag: 'CONNECTION');
        final pingSuccess = await widget.apiService.ping();

        if (mounted) {
          if (pingSuccess) {
            setState(() {
              _isConnected = true;
              _isReconnecting = false;
            });
            timer.cancel();
            _reconnectTimer = null;
            _logger.log('重连成功', tag: 'CONNECTION');
            _refreshFileList();
          } else {
            _logger.log('重连失败：ping返回false (第$reconnectAttempts次)',
                tag: 'CONNECTION');
          }
        }
      } catch (e) {
        _logger.log('重连失败: $e (第$reconnectAttempts次)', tag: 'CONNECTION');
      }
    });
  }

  // 手动重连
  Future<void> _manualReconnect() async {
    setState(() {
      _isReconnecting = true;
    });

    try {
      final pingSuccess = await widget.apiService.ping();
      if (mounted) {
        setState(() {
          _isConnected = pingSuccess;
          _isReconnecting = false;
        });

        if (pingSuccess) {
          _showSuccess('重连成功');
          _refreshFileList();
        } else {
          _showError('重连失败，请检查服务器状态');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
        _showError('重连失败: $e');
      }
    }
  }

  // 主动断开连接
  Future<void> _disconnect() async {
    try {
      _logger.log('主动断开连接', tag: 'CONNECTION');

      // 设置跳过本次自动连接标志（用户主动断开后，本次不自动连接）
      final connectionSettings = ConnectionSettingsService();
      await connectionSettings.setSkipAutoConnectOnce(true);

      // 停止连接检查定时器
      _connectionCheckTimer?.cancel();
      _connectionCheckTimer = null;

      // 停止重连定时器
      _reconnectTimer?.cancel();
      _reconnectTimer = null;

      // 取消WebSocket订阅
      _webSocketSubscription?.cancel();
      _webSocketSubscription = null;

      // 关闭WebSocket连接
      widget.apiService.disconnectWebSocket();

      // 更新连接状态
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isReconnecting = false;
        });
      }

      _logger.log('连接已断开', tag: 'CONNECTION');

      // 返回连接页面
      _returnToConnectionScreen();
    } catch (e) {
      _logger.logError('断开连接失败', error: e);
      // 即使出错也返回连接页面
      _returnToConnectionScreen();
    }
  }

  // 返回连接页面
  void _returnToConnectionScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const DeviceConnectionScreen()),
      (route) => false,
    );
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
      print('增量更新文件列表失败: $e');
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

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('下载完成: $fileName'),
            Text(
              '保存位置: $downloadDir',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '打开文件夹',
          onPressed: () {
            _openFolder(downloadDir);
          },
        ),
      ),
    );
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

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
      ),
    );
  }

  /// 更新预览旋转角度（客户端处理旋转）
  /// 预览旋转角度必须与拍照方向一致，确保预览和拍摄的画面状态一致
  void _updatePreviewRotation() {
    // 客户端根据锁定状态和方向计算旋转角度，与拍照方向一致
    // 锁定状态：sensorOrientation + 90 + lockedRotationAngle（与拍照逻辑一致）
    // 解锁状态：sensorOrientation + currentDeviceOrientation（与拍照逻辑一致）
    final rotationAngle = _orientationLocked
        ? (_sensorOrientation + 90 + _lockedRotationAngle) % 360
        : (_sensorOrientation + _deviceOrientationNotifier.value) % 360;
    _rotationAngleNotifier.value = rotationAngle;
    _logger.log(
        '更新预览旋转角度: ${_orientationLocked ? "锁定" : "解锁"}, 角度=$rotationAngle° (传感器=$_sensorOrientation°, ${_orientationLocked ? "锁定角度=$_lockedRotationAngle°" : "设备方向=${_deviceOrientationNotifier.value}°"})',
        tag: 'PREVIEW');
  }

  /// 旋转预览（锁定状态下）
  Future<void> _rotatePreview() async {
    final newAngle = (_lockedRotationAngle + 90) % 360;
    try {
      // 发送旋转角度到服务器（用于拍照方向）
      final result = await widget.apiService.setLockedRotationAngle(newAngle);
      if (result['success'] == true) {
        setState(() => _lockedRotationAngle = newAngle);
        // 保存到本地存储
        await _orientationPrefs.saveLockedRotationAngle(newAngle);
        // 更新客户端预览旋转角度
        _updatePreviewRotation();
        _showSuccess('预览已旋转到 ${newAngle}°');
      } else {
        _showError('设置旋转角度失败: ${result['error']}');
      }
    } catch (e) {
      _showError('设置旋转角度失败: $e');
    }
  }

  /// 切换方向锁定状态
  Future<void> _toggleOrientationLock() async {
    final newLockState = !_orientationLocked;
    try {
      final result = await widget.apiService.setOrientationLock(newLockState);
      if (result['success'] == true) {
        setState(() {
          _orientationLocked = newLockState;
        });
        // 保存到本地存储
        await _orientationPrefs.saveOrientationLocked(newLockState);
        // 如果切换到锁定状态，确保服务器使用当前的锁定角度
        if (newLockState) {
          await widget.apiService.setLockedRotationAngle(_lockedRotationAngle);
        }
        // 更新客户端预览旋转角度
        _updatePreviewRotation();
        _showSuccess(newLockState ? '方向已锁定' : '方向已解锁');
      } else {
        _showError('设置方向锁定失败: ${result['error']}');
      }
    } catch (e) {
      _showError('设置方向锁定失败: $e');
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          title: Row(
            children: [
              const Text('远程相机控制'),
              const SizedBox(width: 8),
              // 连接状态指示器
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
              ),
              if (_isReconnecting) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            // 断开连接按钮（右上角第一个）
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: _disconnect,
              tooltip: '断开连接',
            ),
            // 重连按钮
            if (!_isConnected)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isReconnecting ? null : _manualReconnect,
                tooltip: '重连',
              ),
            // 返回连接页面按钮
            if (!_isConnected)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _returnToConnectionScreen,
                tooltip: '返回连接页面',
              ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _navigateToSettings,
              tooltip: '设置',
            ),
            IconButton(
              icon: const Icon(Icons.folder),
              onPressed: () => _navigateToFileManager(null),
              tooltip: '文件管理',
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          const dividerWidth = 4.0; // 分割线宽度
          final leftWidth = totalWidth * _leftPanelRatio;
          // 右侧宽度 = 总宽度 - 左侧宽度 - 分割线宽度，确保不溢出
          final rightWidth = totalWidth - leftWidth - dividerWidth;

          return Row(
            children: [
              // 左侧：视频预览区域（根据视频分辨率动态调整宽高比）
              SizedBox(
                width: leftWidth,
                child: Column(
                  children: [
                    // 控制按钮区域
                    Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          // 拍照按钮
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_isOperating || _isRecording)
                                  ? null
                                  : _takePicture,
                              icon: const Icon(Icons.camera, size: 18),
                              label: const Text('拍照',
                                  style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                                backgroundColor: Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 录像按钮
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isOperating ? null : _toggleRecording,
                              icon: Icon(
                                  _isRecording ? Icons.stop : Icons.videocam,
                                  size: 18),
                              label: Text(_isRecording ? '停止' : '录像',
                                  style: const TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                                backgroundColor:
                                    _isRecording ? Colors.red : Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 旋转按钮（只在锁定状态时显示）
                          if (_orientationLocked)
                            IconButton(
                              icon: const Icon(Icons.rotate_90_degrees_cw),
                              color: Colors.blue,
                              onPressed: _rotatePreview,
                              tooltip: '旋转预览（当前: ${_lockedRotationAngle}°）',
                              style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.blue.withOpacity(0.2)),
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
                        ],
                      ),
                    ),
                    // 预览区域
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
                              // 预览窗口：客户端处理旋转，UI层只处理宽高比
                              Positioned.fill(
                                child: ValueListenableBuilder<Map<String, int>>(
                                  valueListenable: _previewSizeNotifier,
                                  builder: (context, previewSize, _) {
                                    return ValueListenableBuilder<int>(
                                      valueListenable: _rotationAngleNotifier,
                                      builder: (context, rotationAngle, _) {
                                        // 计算旋转后的宽高比
                                        var width = previewSize['width'] ?? 640;
                                        var height =
                                            previewSize['height'] ?? 480;

                                        // 如果旋转90度或270度，交换宽高
                                        if (rotationAngle == 90 ||
                                            rotationAngle == 270) {
                                          final temp = width;
                                          width = height;
                                          height = temp;
                                        }

                                        final aspectRatio = width / height;

                                        return AspectRatio(
                                          aspectRatio: aspectRatio,
                                          child: Transform.rotate(
                                            angle:
                                                rotationAngle * math.pi / 180,
                                            child: MjpegStreamWidget(
                                              streamUrl: widget.apiService
                                                  .getPreviewStreamUrl(),
                                              previewWidth:
                                                  previewSize['width'],
                                              previewHeight:
                                                  previewSize['height'],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 可拖拽的分割线
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final newLeftWidth = leftWidth + details.delta.dx;
                    final newRatio = newLeftWidth / totalWidth;
                    // 限制比例在 0.2 到 0.7 之间
                    _leftPanelRatio = newRatio.clamp(0.2, 0.7);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: SizedBox(
                    width: dividerWidth,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

              // 右侧：直接嵌入完整的文件管理界面（无 AppBar）
              SizedBox(
                width: rightWidth,
                child: ClipRect(
                  child: FileManagerScreen(
                    apiService: widget.apiService,
                    highlightFileName: null,
                    showAppBar: false,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 导航到文件管理并定位到指定文件（全屏模式）
  void _navigateToFileManager(String? fileName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileManagerScreen(
          apiService: widget.apiService,
          highlightFileName: fileName,
        ),
      ),
    );
  }

  /// 在系统资源管理器中打开并选中文件
  Future<void> _openInFileManager(FileInfo file) async {
    try {
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);

      if (!await localFile.exists()) {
        _showInfo('文件不存在');
        return;
      }

      // 跨平台打开文件管理器并选中文件
      if (Platform.isMacOS) {
        // macOS: open -R
        await Process.run('open', ['-R', localPath]);
      } else if (Platform.isWindows) {
        // Windows: explorer /select,filepath
        await Process.run('explorer', ['/select,', localPath]);
      } else if (Platform.isLinux) {
        // Linux: xdg-open (打开目录)
        final dirPath = path.dirname(localPath);
        await Process.run('xdg-open', [dirPath]);
      } else {
        _showInfo('不支持的操作系统');
      }

      _showInfo('已在资源管理器中打开');
    } catch (e) {
      _showInfo('打开资源管理器失败: $e');
    }
  }

  /// 复制文件到剪贴板（跨平台）
  Future<void> _copyFile(FileInfo file) async {
    try {
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);

      if (!await localFile.exists()) {
        _showInfo('文件不存在');
        return;
      }

      // 跨平台复制文件到剪贴板
      if (Platform.isMacOS) {
        // macOS: 使用 osascript 复制文件引用
        try {
          final escapedPath =
              localPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
          // 使用 POSIX file 复制文件引用，而不是文件内容
          final script = 'set the clipboard to POSIX file "$escapedPath"';
          final result = await Process.run('osascript', ['-e', script]);
          if (result.exitCode == 0) {
            _showInfo('文件已复制到剪贴板');
          } else {
            // 如果失败，复制文件路径
            await Clipboard.setData(ClipboardData(text: localPath));
            _showInfo('文件路径已复制到剪贴板');
          }
        } catch (e) {
          // 如果失败，复制文件路径
          await Clipboard.setData(ClipboardData(text: localPath));
          _showInfo('文件路径已复制到剪贴板');
        }
      } else if (Platform.isWindows) {
        // Windows: 使用 PowerShell 复制文件
        try {
          final escapedPath =
              localPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
          final result = await Process.run('powershell', [
            '-Command',
            'Set-Clipboard -Path "$escapedPath"',
          ]);
          if (result.exitCode == 0) {
            _showInfo('文件已复制到剪贴板');
          } else {
            await Clipboard.setData(ClipboardData(text: localPath));
            _showInfo('文件路径已复制到剪贴板');
          }
        } catch (e) {
          await Clipboard.setData(ClipboardData(text: localPath));
          _showInfo('文件路径已复制到剪贴板');
        }
      } else if (Platform.isLinux) {
        // Linux: 使用 xclip 复制文件
        try {
          final fileBytes = await localFile.readAsBytes();
          final process = await Process.start('xclip', [
            '-selection',
            'clipboard',
            '-t',
            file.isVideo ? 'video/mp4' : 'image/png'
          ]);
          process.stdin.add(fileBytes);
          await process.stdin.close();
          final exitCode = await process.exitCode;
          if (exitCode == 0) {
            _showInfo('文件已复制到剪贴板');
          } else {
            throw Exception('xclip failed with exit code $exitCode');
          }
        } catch (e) {
          try {
            final fileBytes = await localFile.readAsBytes();
            final process =
                await Process.start('xsel', ['--clipboard', '--input']);
            process.stdin.add(fileBytes);
            await process.stdin.close();
            final exitCode = await process.exitCode;
            if (exitCode == 0) {
              _showInfo('文件已复制到剪贴板');
            } else {
              throw Exception('xsel failed with exit code $exitCode');
            }
          } catch (e2) {
            await Clipboard.setData(ClipboardData(text: localPath));
            _showInfo('文件路径已复制到剪贴板（请安装 xclip 或 xsel 以支持文件复制）');
          }
        }
      } else {
        await Clipboard.setData(ClipboardData(text: localPath));
        _showInfo('文件路径已复制到剪贴板');
      }
    } catch (e) {
      _showInfo('复制失败: $e');
    }
  }

  /// 删除本地文件
  Future<void> _deleteLocalFile(FileInfo file) async {
    try {
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);

      if (!await localFile.exists()) {
        _showInfo('文件不存在');
        return;
      }

      // 确认对话框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除本地文件 ${file.name} 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      await localFile.delete();
      _downloadedStatusCache[file.name] = false;
      setState(() {});
      _showInfo('本地文件已删除');
    } catch (e) {
      _showInfo('删除失败: $e');
    }
  }

  /// 下载文件
  Future<void> _downloadFile(FileInfo file) async {
    try {
      // 检查是否已下载
      final isDownloaded = _downloadedStatusCache[file.name] == true;
      if (isDownloaded) {
        _showInfo('文件已下载');
        return;
      }

      // 检查是否正在下载
      final existingTask = await _downloadManager.findTaskByFileName(file.name);
      if (existingTask != null &&
          (existingTask.status == DownloadStatus.downloading ||
              existingTask.status == DownloadStatus.pending)) {
        _showInfo('文件正在下载中');
        return;
      }

      await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );

      final downloadDir = await _downloadSettings.getDownloadPath();
      _showInfo('已添加到下载队列\n保存位置: $downloadDir');
    } catch (e) {
      _showInfo('添加下载失败: $e');
    }
  }
}
