import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';
import '../services/camera_service.dart';
import '../services/settings_service.dart';
import '../services/http_server.dart';
import '../services/logger_service.dart';
import '../services/operation_log_service.dart';
import '../services/foreground_service.dart';
import '../models/camera_status.dart';
import 'debug_log_screen.dart';
import 'server_settings_screen.dart';
import '../main.dart';

class ServerHomePage extends StatefulWidget {
  const ServerHomePage({Key? key}) : super(key: key);

  @override
  State<ServerHomePage> createState() => _ServerHomePageState();
}

class _ServerHomePageState extends State<ServerHomePage> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final SettingsService _settingsService = SettingsService();
  final LoggerService _logger = LoggerService();
  final ForegroundService _foregroundService = ForegroundService();
  late HttpServerService _httpServer;
  
  bool _isInitialized = false;
  bool _isServerRunning = false;
  String? _ipAddress;
  final int _port = 8080;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRefreshTimer();
    _httpServer.stop();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 应用切回前台时，检查并恢复预览流
      _logger.log('应用切回前台，检查预览流状态', tag: 'LIFECYCLE');
      _checkAndRestorePreviewStream();
    } else if (state == AppLifecycleState.paused) {
      _logger.log('应用切到后台', tag: 'LIFECYCLE');
    }
  }

  /// 检查并恢复预览流
  Future<void> _checkAndRestorePreviewStream() async {
    if (!_isInitialized || !_isServerRunning) {
      return;
    }

    try {
      // 检查相机是否已初始化
      if (!_cameraService.isInitialized) {
        _logger.log('相机未初始化，无法恢复预览流', tag: 'LIFECYCLE');
        return;
      }

      // 等待一小段时间，让应用完全恢复
      await Future.delayed(const Duration(milliseconds: 500));

      // 尝试恢复预览流
      _logger.log('尝试恢复预览流', tag: 'LIFECYCLE');
      await _cameraService.resumePreview();
      
      // 等待一段时间后检查预览帧是否恢复
      await Future.delayed(const Duration(milliseconds: 1000));
      
      final lastFrame = _cameraService.lastPreviewFrame;
      if (lastFrame == null) {
        _logger.log('预览帧仍为null，预览流可能未恢复', tag: 'LIFECYCLE');
      } else {
        _logger.log('预览流已恢复，最后预览帧大小: ${lastFrame.length} 字节', tag: 'LIFECYCLE');
      }
    } catch (e, stackTrace) {
      _logger.logError('检查预览流状态失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 检查并请求忽略电池优化
  Future<void> _checkBatteryOptimization() async {
    try {
      final isIgnoring = await _foregroundService.isIgnoringBatteryOptimizations();
      if (!isIgnoring) {
        _logger.log('应用未忽略电池优化，将请求用户授权', tag: 'BATTERY');
        // 延迟一下，避免在启动时立即弹出对话框
        await Future.delayed(const Duration(seconds: 2));
        await _foregroundService.requestIgnoreBatteryOptimizations();
      } else {
        _logger.log('应用已忽略电池优化', tag: 'BATTERY');
      }
    } catch (e, stackTrace) {
      _logger.logError('检查电池优化状态失败', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _initializeServices() async {
    try {
      // 初始化日志服务
      await _logger.initialize();
      _logger.log('应用启动', tag: 'INIT');
      
      // 检查并请求相机权限
      final cameraStatus = await Permission.camera.status;
      _logger.log('相机权限状态: $cameraStatus', tag: 'PERMISSION');
      
      if (!cameraStatus.isGranted) {
        _logger.log('请求相机权限', tag: 'PERMISSION');
        final result = await Permission.camera.request();
        _logger.log('相机权限请求结果: $result', tag: 'PERMISSION');
        
        if (!result.isGranted) {
          setState(() {
            _errorMessage = '需要相机权限才能使用此应用';
          });
          _logger.logError('相机权限被拒绝');
          return;
        }
      }
      
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = '未检测到相机';
        });
        _logger.logError('相机初始化失败: 未检测到相机');
        return;
      }

      // 加载设置
      final settings = await _settingsService.loadSettings();
      _logger.log('设置已加载: ${settings.toJson()}', tag: 'INIT');

      // 初始化文件索引服务（不启动相机，相机在服务器启动时才启动）
      await _cameraService.initializeFileIndex();
      _logger.log('文件索引服务已初始化', tag: 'INIT');
      _logger.log('注意：相机服务将在服务器启动时初始化，以节省电量', tag: 'INIT');

      // 创建HTTP服务器
      _httpServer = HttpServerService(
        cameraService: _cameraService,
        settingsService: _settingsService,
      );
      
      // 设置自动停止回调
      _httpServer.setAutoStopCallback(() {
        _logger.log('自动停止服务器触发', tag: 'AUTO_STOP');
        _stopServer();
      });

      setState(() {
        _isInitialized = true;
      });
      
      // 检查是否自动启动
      final autoStart = await ServerSettings.getAutoStart();
      if (autoStart) {
        _logger.log('自动启动服务器', tag: 'AUTO');
        await _startServer();
      }
    } catch (e, stackTrace) {
      _logger.logError('初始化失败', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = '初始化失败: $e';
      });
    }
  }

  Future<void> _startServer() async {
    try {
      _logger.log('正在启动服务器...', tag: 'SERVER');
      
      // 服务器启动时初始化相机服务（节省电量：服务器未启动时不使用相机）
      if (!_cameraService.isInitialized) {
        _logger.log('初始化相机服务...', tag: 'SERVER');
        
        // 选择相机：优先使用后置相机作为主相机
        CameraDescription mainCamera;
        
        // 列出所有可用相机
        _logger.log('可用相机列表:', tag: 'SERVER');
        for (var camera in cameras) {
          _logger.log('  - ${camera.name}, 方向: ${camera.lensDirection}', tag: 'SERVER');
        }
        
        // 查找后置相机（主相机）
        try {
          mainCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
          );
          _logger.log('找到后置相机作为主相机: ${mainCamera.name}', tag: 'SERVER');
        } catch (e) {
          // 如果没有后置相机，使用第一个相机（可能是前置）
          mainCamera = cameras.first;
          _logger.log('未找到后置相机，使用第一个相机作为主相机: ${mainCamera.name}, 方向: ${mainCamera.lensDirection}', tag: 'SERVER');
        }
        
        // 加载设置
        final settings = await _settingsService.loadSettings();
        
        // 使用单相机模式（原生相机支持同时录制和预览）
        await _cameraService.initialize(mainCamera, settings);
        _logger.logCamera('相机初始化成功（单相机模式）', details: '相机: ${mainCamera.name} (${mainCamera.lensDirection})');
        _logger.log('注意：录制时预览可能停止，取决于设备硬件支持', tag: 'SERVER');
      }
      
      // 启动HTTP服务器（此时后台服务会自动启动）
      _ipAddress = await _httpServer.start(_port);
      setState(() {
        _isServerRunning = true;
      });
      
      _logger.log('服务器启动成功: http://$_ipAddress:$_port', tag: 'SERVER');
      
      // 检查并请求忽略电池优化（仅在Android上）
      if (Platform.isAndroid) {
        await _checkBatteryOptimization();
      }
      
      // 启动定时刷新UI（每2秒刷新一次连接设备列表）
      _startRefreshTimer();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('服务器已启动: http://$_ipAddress:$_port'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      _logger.logError('启动服务器失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动服务器失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopServer() async {
    _logger.log('正在停止服务器...', tag: 'SERVER');
    
    // 停止HTTP服务器（此时后台服务会自动停止）
    await _httpServer.stop();
    
    // 停止相机服务（节省电量：服务器停止时不使用相机）
    if (_cameraService.isInitialized) {
      _logger.log('停止相机服务...', tag: 'SERVER');
      await _cameraService.dispose();
      _logger.log('相机服务已停止', tag: 'SERVER');
    }
    
    // 停止定时刷新
    _stopRefreshTimer();
    
    setState(() {
      _isServerRunning = false;
    });
    
    _logger.log('服务器已停止', tag: 'SERVER');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('服务器已停止'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
  
  // 启动定时刷新
  void _startRefreshTimer() {
    _stopRefreshTimer(); // 先停止已有的定时器
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && _isServerRunning) {
        setState(() {
          // 触发UI刷新，更新连接设备列表
        });
      } else {
        _stopRefreshTimer();
      }
    });
  }
  
  // 停止定时刷新
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }


  void _navigateToDebugLog() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const DebugLogScreen()),
    );
  }

  void _navigateToSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ServerSettingsScreen()),
    );
    // 设置页面返回后，更新自动停止设置
    if (_isServerRunning) {
      await _httpServer.updateAutoStopSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('远程相机服务端'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                  _initializeServices();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('远程相机服务端'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('远程相机服务端'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _navigateToDebugLog,
            tooltip: '调试日志',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
            tooltip: '设置',
          ),
        ],
      ),
      body: Column(
        children: [
          // 控制按钮（移到最上面）
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isServerRunning ? null : _startServer,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('启动服务器'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isServerRunning ? _stopServer : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止服务器'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 服务器状态卡片
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isServerRunning ? Icons.check_circle : Icons.cancel,
                        color: _isServerRunning ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '服务器状态: ${_isServerRunning ? "运行中" : "已停止"}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_isServerRunning && _ipAddress != null) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),
                    _buildInfoRow('IP地址', _ipAddress!),
                    const SizedBox(height: 8),
                    _buildInfoRow('端口', _port.toString()),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      '相机状态',
                      _cameraService.status.displayName,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      '已连接设备',
                      '${_httpServer.connectedDeviceCount} 台',
                    ),
                    if (_httpServer.connectedDeviceCount > 0) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        '已连接客户端:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._httpServer.connectedDevices.map((device) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.devices, size: 18, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  device.ipAddress,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getTimeSince(device.lastActivity),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 关键操作记录窗口
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: const [
                        Icon(Icons.history, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '操作记录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildOperationLogs(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildOperationLogs() {
    final logs = _httpServer.operationLog.getLogs();
    
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          '暂无操作记录',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _buildLogItem(log);
      },
    );
  }

  Widget _buildLogItem(OperationLog log) {
    final timeStr = _formatTime(log.timestamp);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _getOperationIcon(log.type),
            size: 20,
            color: _getOperationColor(log.type),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.displayText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      log.clientIp,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '·',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getOperationIcon(OperationType type) {
    switch (type) {
      case OperationType.takePicture:
        return Icons.camera_alt;
      case OperationType.startRecording:
        return Icons.videocam;
      case OperationType.stopRecording:
        return Icons.videocam_off;
      case OperationType.downloadStart:
        return Icons.download;
      case OperationType.downloadComplete:
        return Icons.check_circle;
      case OperationType.connect:
        return Icons.link;
      case OperationType.disconnect:
        return Icons.link_off;
    }
  }

  Color _getOperationColor(OperationType type) {
    switch (type) {
      case OperationType.takePicture:
        return Colors.blue;
      case OperationType.startRecording:
        return Colors.red;
      case OperationType.stopRecording:
        return Colors.orange;
      case OperationType.downloadStart:
        return Colors.blue;
      case OperationType.downloadComplete:
        return Colors.green;
      case OperationType.connect:
        return Colors.teal;
      case OperationType.disconnect:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else {
      return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  String _getTimeSince(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '${diff.inHours}小时前';
    }
  }

}
