import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/api_service_manager.dart';
import '../services/websocket_connection.dart' as ws;
import '../services/logger_service.dart';
import '../services/capture_settings_service.dart';
import '../services/connection_settings_service.dart';
import '../services/device_config_service.dart';
import '../services/update_service.dart';
import '../screens/library/library_screen.dart';
import '../screens/capture/local_camera_screen.dart';
import '../screens/client_settings_screen.dart';
import '../screens/camera_control_screen.dart';
import '../core/core.dart';
import 'connection_dialog.dart';

/// 自适应导航外壳
/// 
/// 根据屏幕宽度自动切换布局：
/// - 窄屏（< 600px）：底部导航栏
/// - 宽屏（>= 600px）：左侧导航栏
/// 
/// 底部常驻连接状态栏，显示远端服务连接状态
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  final ClientLoggerService _logger = ClientLoggerService();
  final ApiServiceManager _apiManager = ApiServiceManager();
  final CaptureSettingsService _captureSettings = CaptureSettingsService();
  final UpdateService _updateService = UpdateService();
  
  int _currentIndex = 0;
  bool _isRemoteConnected = false;
  String? _connectedHost;
  StreamSubscription? _connectionSubscription;
  StreamSubscription<ws.ConnectionStateChange>? _detailedConnectionSubscription;
  CaptureSource _captureSource = CaptureSource.remoteCamera;
  bool _hasUpdate = false;
  Timer? _updateCheckTimer;
  
  // 详细连接状态
  ws.ConnectionState _connectionState = ws.ConnectionState.disconnected;
  int _reconnectAttempts = 0;
  int _maxReconnectAttempts = 20;
  
  // 媒体库服务
  late final MediaLibraryService _libraryService;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _checkRemoteConnection();
    _loadCaptureSource();
    _initUpdateCheck();
    _tryAutoConnect();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _detailedConnectionSubscription?.cancel();
    _updateCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      _logger.log('初始化媒体库服务...', tag: 'SHELL');
      _libraryService = MediaLibraryService.instance;
      await _libraryService.init();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      _logger.log('媒体库服务初始化完成', tag: 'SHELL');
    } catch (e, stackTrace) {
      _logger.logError('初始化媒体库服务失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isInitialized = true; // 即使失败也显示界面
        });
      }
    }
  }

  Future<void> _loadCaptureSource() async {
    final source = await _captureSettings.getCaptureSource();
    if (mounted) {
      setState(() {
        _captureSource = source;
      });
    }
  }

  /// 尝试自动连接（如果启用了自动连接且未跳过）
  Future<void> _tryAutoConnect() async {
    try {
      final settings = await ConnectionSettingsService().getConnectionSettings();
      final autoConnect = settings['autoConnect'] as bool? ?? true;
      
      if (!autoConnect) {
        _logger.log('自动连接已禁用', tag: 'AUTO_CONNECT');
        return;
      }
      
      // 检查是否跳过本次自动连接（用户主动断开后）
      final shouldSkip = await ConnectionSettingsService().shouldSkipAutoConnectOnce();
      if (shouldSkip) {
        _logger.log('跳过本次自动连接', tag: 'AUTO_CONNECT');
        // 清除跳过标记
        await ConnectionSettingsService().setSkipAutoConnectOnce(false);
        return;
      }
      
      // 检查是否已经连接
      if (_isRemoteConnected) {
        _logger.log('已连接，跳过自动连接', tag: 'AUTO_CONNECT');
        return;
      }
      
      // 延迟一小段时间再自动连接，让界面先显示出来
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted) return;
      
      _logger.log('启动自动连接...', tag: 'AUTO_CONNECT');
      await _connectDirectly();
    } catch (e) {
      _logger.logError('自动连接失败', error: e);
    }
  }

  /// 初始化更新检查（启动时检查 + 每小时检查）
  void _initUpdateCheck() {
    // 启动时检查（main.dart 已经做了，这里只读取缓存）
    _checkUpdateStatus();
    
    // 每小时检查一次
    _updateCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _checkForUpdatePeriodically();
    });
  }

  /// 检查缓存的更新状态
  Future<void> _checkUpdateStatus() async {
    final updateInfo = await _updateService.getSavedUpdateInfo();
    if (mounted) {
      setState(() {
        _hasUpdate = updateInfo != null;
      });
    }
  }

  /// 定时检查更新
  Future<void> _checkForUpdatePeriodically() async {
    try {
      _logger.log('定时检查更新...', tag: 'UPDATE');
      await _updateService.initializeUpdateUrls();
      final result = await _updateService.checkForUpdate(avoidCache: true);
      if (mounted) {
        setState(() {
          _hasUpdate = result.hasUpdate;
        });
      }
      if (result.hasUpdate) {
        _logger.log('发现新版本: ${result.updateInfo?.version}', tag: 'UPDATE');
      }
    } catch (e) {
      _logger.logError('定时检查更新失败', error: e);
    }
  }

  void _checkRemoteConnection() {
    // 检查当前连接状态
    final apiService = _apiManager.getCurrentApiService();
    setState(() {
      _isRemoteConnected = apiService != null && apiService.isWebSocketConnected;
      _connectedHost = apiService?.host;
      _connectionState = _apiManager.connectionState ?? ws.ConnectionState.disconnected;
    });
    
    // 如果已连接，同步云端文件并监听详细状态
    if (apiService != null) {
      _startListeningDetailedConnectionState(apiService);
      if (_isRemoteConnected) {
        _syncRemoteFilesToLibrary(apiService);
      }
    }
    
    // 监听连接状态变化（ApiService 实例的变化）
    _connectionSubscription = _apiManager.connectionStateStream.listen((connected) {
      if (mounted) {
        final apiService = _apiManager.getCurrentApiService();
        
        // 取消之前的详细状态监听
        _detailedConnectionSubscription?.cancel();
        _detailedConnectionSubscription = null;
        
        setState(() {
          _isRemoteConnected = connected;
          _connectedHost = connected ? apiService?.host : null;
          _connectionState = connected ? ws.ConnectionState.registered : ws.ConnectionState.disconnected;
          _reconnectAttempts = 0;
        });
        
        // 连接成功时同步云端文件并监听详细状态
        if (connected && apiService != null) {
          _startListeningDetailedConnectionState(apiService);
          _syncRemoteFilesToLibrary(apiService);
        } else if (!connected) {
          _clearRemoteFilesFromLibrary();
        }
      }
    });
  }
  
  /// 开始监听详细的 WebSocket 连接状态
  void _startListeningDetailedConnectionState(dynamic apiService) {
    _detailedConnectionSubscription?.cancel();
    _detailedConnectionSubscription = apiService.connectionStateStream.listen(
      (ws.ConnectionStateChange stateChange) {
        if (!mounted) return;
        
        final newState = stateChange.newState;
        _logger.log('详细连接状态变化: ${stateChange.oldState} -> $newState', tag: 'SHELL');
        
        setState(() {
          _connectionState = newState;
          
          // 更新重连次数
          if (stateChange.data != null && stateChange.data!['attempt'] != null) {
            _reconnectAttempts = stateChange.data!['attempt'] as int;
          }
          if (stateChange.data != null && stateChange.data!['maxAttempts'] != null) {
            _maxReconnectAttempts = stateChange.data!['maxAttempts'] as int;
          }
          
          // 更新连接状态
          _isRemoteConnected = newState == ws.ConnectionState.connected || 
                               newState == ws.ConnectionState.registered;
        });
      },
    );
  }

  /// 同步云端文件到本地媒体库
  Future<void> _syncRemoteFilesToLibrary(dynamic apiService) async {
    try {
      _logger.log('开始同步云端文件到媒体库...', tag: 'SYNC');
      
      // 获取云端文件列表
      final result = await apiService.getFileList();
      if (result['success'] != true) {
        _logger.log('获取云端文件列表失败', tag: 'SYNC');
        return;
      }
      
      final pictures = result['pictures'] as List<dynamic>? ?? [];
      final videos = result['videos'] as List<dynamic>? ?? [];
      
      // 合并所有文件
      final allFiles = <dynamic>[...pictures, ...videos];
      
      if (allFiles.isEmpty) {
        _logger.log('云端没有文件', tag: 'SYNC');
        return;
      }
      
      // 同步到媒体库（传入 baseUrl 以下载缩略图）
      final addedCount = await _libraryService.syncRemoteFiles(
        allFiles.cast(),
        baseUrl: apiService.baseUrl,
      );
      
      _logger.log('同步完成，新增 $addedCount 个云端文件', tag: 'SYNC');
    } catch (e, stackTrace) {
      _logger.logError('同步云端文件失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 清除媒体库中的云端文件
  Future<void> _clearRemoteFilesFromLibrary() async {
    try {
      _logger.log('清除媒体库中的云端文件...', tag: 'SYNC');
      final clearedCount = await _libraryService.clearRemoteFiles();
      _logger.log('已清除 $clearedCount 个云端文件', tag: 'SYNC');
    } catch (e, stackTrace) {
      _logger.logError('清除云端文件失败', error: e, stackTrace: stackTrace);
    }
  }

  void _onNavigationChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  /// 直接连接（使用保存的设置）
  Future<void> _connectDirectly() async {
    try {
      final settings = await ConnectionSettingsService().getConnectionSettings();
      final host = settings['host'] as String;
      final port = settings['port'] as int;
      
      _logger.log('直接连接到 $host:$port', tag: 'CONNECTION');
      
      // 显示连接中状态
      setState(() {
        _connectionState = ws.ConnectionState.connecting;
      });
      
      final apiService = ApiService(host: host, port: port);
      ApiServiceManager().setCurrentApiService(apiService);
      
      // 测试连接
      final pingError = await apiService.ping();
      
      if (!mounted) return;
      
      if (pingError == null && apiService.isWebSocketConnected) {
        // 连接成功，获取设备信息并注册
        try {
          final deviceInfoResult = await apiService.getDeviceInfo();
          if (deviceInfoResult['success'] == true && deviceInfoResult['deviceInfo'] != null) {
            final deviceInfo = deviceInfoResult['deviceInfo'] as Map<String, dynamic>;
            final deviceModel = deviceInfo['model'] as String?;
            if (deviceModel != null && deviceModel.isNotEmpty) {
              await apiService.registerDevice(deviceModel);
              
              // 应用保存的设备配置
              final savedConfig = await DeviceConfigService().getDeviceConfig(deviceModel);
              if (savedConfig != null) {
                await apiService.updateSettings(savedConfig);
              }
            }
          }
        } catch (e) {
          _logger.logError('获取/应用设备配置失败', error: e);
        }
        
        _logger.log('连接成功', tag: 'CONNECTION');
        _checkRemoteConnection();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已连接到 $host'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // 连接失败，显示对话框让用户修改设置
        _logger.log('直接连接失败，打开设置对话框', tag: 'CONNECTION');
        ApiServiceManager().setCurrentApiService(null);
        setState(() {
          _connectionState = ws.ConnectionState.disconnected;
        });
        _openConnectionDialog();
      }
    } catch (e) {
      _logger.logError('直接连接失败', error: e);
      setState(() {
        _connectionState = ws.ConnectionState.disconnected;
      });
      _openConnectionDialog();
    }
  }

  /// 打开连接对话框
  void _openConnectionDialog() {
    ConnectionDialog.show(context, onConnected: () {
      // 连接成功后刷新状态
      _checkRemoteConnection();
    });
  }

  /// 断开连接
  Future<void> _disconnect() async {
    try {
      // 设置跳过本次自动连接（避免断开后立即重连）
      await ConnectionSettingsService().setSkipAutoConnectOnce(true);
      
      await _apiManager.gracefulDisconnect();
      _apiManager.setCurrentApiService(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已断开连接'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      _logger.logError('断开连接失败', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 600;
        
        if (isWideScreen) {
          return _buildDesktopLayout();
        } else {
          return _buildMobileLayout();
        }
      },
    );
  }

  /// 桌面布局：左侧导航栏 + 右侧内容
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // 左侧导航栏
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onNavigationChanged,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Icon(
                Icons.camera_alt,
                size: 32,
                color: Theme.of(context).primaryColor,
              ),
            ),
            trailing: Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 连接状态指示器
                  _buildConnectionIndicator(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: Text('媒体库'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.camera_alt_outlined),
                selectedIcon: Icon(Icons.camera_alt),
                label: Text('拍摄'),
              ),
              NavigationRailDestination(
                icon: _buildSettingsIcon(false),
                selectedIcon: _buildSettingsIcon(true),
                label: const Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // 右侧内容区域
          Expanded(
            child: _buildPageContent(),
          ),
        ],
      ),
    );
  }

  /// 移动端布局：内容 + 底部导航栏（连接状态集成到导航栏）
  Widget _buildMobileLayout() {
    return Scaffold(
      body: _buildPageContent(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onNavigationChanged,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: '媒体库',
          ),
          NavigationDestination(
            icon: _buildMobileConnectionIcon(false),
            selectedIcon: _buildMobileConnectionIcon(true),
            label: '拍摄',
          ),
          NavigationDestination(
            icon: _buildSettingsIcon(false),
            selectedIcon: _buildSettingsIcon(true),
            label: '设置',
          ),
        ],
      ),
    );
  }
  
  /// 移动端拍摄图标（带连接状态指示）
  Widget _buildMobileConnectionIcon(bool selected) {
    final isReconnecting = _connectionState == ws.ConnectionState.reconnecting;
    final statusColor = _isRemoteConnected 
        ? Colors.green 
        : (isReconnecting ? Colors.orange : Colors.grey);
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(selected ? Icons.camera_alt : Icons.camera_alt_outlined),
        // 连接状态小圆点
        Positioned(
          right: -4,
          top: -4,
          child: isReconnecting
              ? const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                )
              : Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 构建设置图标（带红点提示）
  Widget _buildSettingsIcon(bool selected) {
    return Badge(
      isLabelVisible: _hasUpdate,
      child: Icon(selected ? Icons.settings : Icons.settings_outlined),
    );
  }

  /// 页面内容（根据当前索引显示不同页面）
  Widget _buildPageContent() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        // 媒体库页面
        LibraryScreen(libraryService: _libraryService),
        // 拍摄页面（根据设置决定内容）
        _buildCapturePage(),
        // 设置页面
        ClientSettingsScreen(
          onCaptureSourceChanged: _loadCaptureSource,
          onUpdateStatusChanged: _checkUpdateStatus,
        ),
      ],
    );
  }

  /// 构建拍摄页面
  Widget _buildCapturePage() {
    if (_captureSource == CaptureSource.localCamera && 
        _captureSettings.isLocalCameraSupported()) {
      // 本机摄像头
      return const LocalCameraScreen();
    } else {
      // 远端相机
      if (_isRemoteConnected) {
        // 已连接，显示相机控制
        final apiService = _apiManager.getCurrentApiService();
        if (apiService != null) {
          return CameraControlScreen(apiService: apiService);
        }
      }
      // 未连接，显示提示页面
      return _buildRemoteCameraPlaceholder();
    }
  }

  /// 远端相机未连接时的占位页面
  Widget _buildRemoteCameraPlaceholder() {
    final isConnecting = _connectionState == ws.ConnectionState.connecting;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('远端相机'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_android_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              '未连接远端相机',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请先连接手机相机服务',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: isConnecting ? null : _connectDirectly,
              icon: isConnecting 
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(isConnecting ? '连接中...' : '连接远端相机'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面端导航栏底部的连接状态指示器
  Widget _buildConnectionIndicator() {
    final isReconnecting = _connectionState == ws.ConnectionState.reconnecting;
    final isConnecting = _connectionState == ws.ConnectionState.connecting;
    final statusColor = _isRemoteConnected 
        ? Colors.green 
        : (isReconnecting || isConnecting ? Colors.orange : Colors.grey);
    
    return GestureDetector(
      onTap: _isRemoteConnected ? _disconnect : _connectDirectly,
      child: Tooltip(
        message: _getConnectionTooltip(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isReconnecting || isConnecting)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                )
              else
                Icon(
                  _isRemoteConnected ? Icons.link : Icons.link_off,
                  color: statusColor,
                  size: 24,
                ),
              const SizedBox(height: 4),
              if (isReconnecting)
                Text(
                  '$_reconnectAttempts/$_maxReconnectAttempts',
                  style: const TextStyle(fontSize: 10, color: Colors.orange),
                )
              else if (isConnecting)
                const Text(
                  '连接中',
                  style: TextStyle(fontSize: 10, color: Colors.orange),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 获取连接状态提示文字
  String _getConnectionTooltip() {
    if (_isRemoteConnected) {
      return '已连接 $_connectedHost\n点击断开';
    } else if (_connectionState == ws.ConnectionState.reconnecting) {
      return '正在重连 ($_reconnectAttempts/$_maxReconnectAttempts)...';
    } else {
      return '未连接\n点击连接';
    }
  }
}
