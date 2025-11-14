import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import '../services/camera_service.dart';
import '../services/settings_service.dart';
import '../services/http_server.dart';
import '../services/logger_service.dart';
import '../models/camera_status.dart';
import 'debug_log_screen.dart';
import 'server_settings_screen.dart';
import '../main.dart';

class ServerHomePage extends StatefulWidget {
  const ServerHomePage({Key? key}) : super(key: key);

  @override
  State<ServerHomePage> createState() => _ServerHomePageState();
}

class _ServerHomePageState extends State<ServerHomePage> {
  final CameraService _cameraService = CameraService();
  final SettingsService _settingsService = SettingsService();
  final LoggerService _logger = LoggerService();
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
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // 初始化日志服务
      await _logger.initialize();
      _logger.log('应用启动', tag: 'INIT');
      
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

      // 初始化文件索引服务
      await _cameraService.initializeFileIndex();
      _logger.log('文件索引服务已初始化', tag: 'INIT');
      
      // 选择相机：优先使用后置相机作为主相机
      // 注意：根据搜索结果，大多数Android设备不支持同时使用前后摄像头
      // 因此我们使用单相机模式，尝试在录制时继续使用图像流进行预览
      CameraDescription mainCamera;
      
      // 列出所有可用相机
      _logger.log('可用相机列表:', tag: 'INIT');
      for (var camera in cameras) {
        _logger.log('  - ${camera.name}, 方向: ${camera.lensDirection}', tag: 'INIT');
      }
      
      // 查找后置相机（主相机）
      try {
        mainCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
        _logger.log('找到后置相机作为主相机: ${mainCamera.name}', tag: 'INIT');
      } catch (e) {
        // 如果没有后置相机，使用第一个相机（可能是前置）
        mainCamera = cameras.first;
        _logger.log('未找到后置相机，使用第一个相机作为主相机: ${mainCamera.name}, 方向: ${mainCamera.lensDirection}', tag: 'INIT');
      }
      
      // 使用单相机模式（原生相机支持同时录制和预览）
      await _cameraService.initialize(mainCamera, settings);
      _logger.logCamera('相机初始化成功（单相机模式）', details: '相机: ${mainCamera.name} (${mainCamera.lensDirection})');
      _logger.log('注意：录制时预览可能停止，取决于设备硬件支持', tag: 'INIT');

      // 创建HTTP服务器
      _httpServer = HttpServerService(
        cameraService: _cameraService,
        settingsService: _settingsService,
      );

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
      _ipAddress = await _httpServer.start(_port);
      setState(() {
        _isServerRunning = true;
      });
      
      _logger.log('服务器启动成功: http://$_ipAddress:$_port', tag: 'SERVER');
      
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
    await _httpServer.stop();
    
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

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ServerSettingsScreen()),
    );
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

          // 相机预览
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _cameraService.isInitialized
                    ? Stack(
                        children: [
                          Center(
                            child: Container(
                              color: Colors.black,
                              child: const Center(
                                child: Text(
                                  '预览通过客户端查看',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                          if (_cameraService.isRecording)
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
                      )
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
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

  @override
  void dispose() {
    _stopRefreshTimer();
    _httpServer.stop();
    _cameraService.dispose();
    super.dispose();
  }
}
