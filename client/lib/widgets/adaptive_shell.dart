import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service_manager.dart';
import '../services/logger_service.dart';
import '../services/capture_settings_service.dart';
import '../services/update_service.dart';
import '../screens/library/library_screen.dart';
import '../screens/capture/local_camera_screen.dart';
import '../screens/client_settings_screen.dart';
import '../screens/camera_control_screen.dart';
import '../core/core.dart';
import 'connection_dialog.dart';
import 'package:shared/shared.dart';

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
  CaptureSource _captureSource = CaptureSource.remoteCamera;
  bool _hasUpdate = false;
  Timer? _updateCheckTimer;
  
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
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
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
      _isRemoteConnected = apiService != null;
      _connectedHost = apiService?.host;
    });
    
    // 监听连接状态变化
    _connectionSubscription = _apiManager.connectionStateStream.listen((connected) {
      if (mounted) {
        final apiService = _apiManager.getCurrentApiService();
        setState(() {
          _isRemoteConnected = connected;
          _connectedHost = connected ? apiService?.host : null;
        });
      }
    });
  }

  void _onNavigationChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  /// 打开连接对话框
  void _openConnectionDialog() {
    ConnectionDialog.show(context, onConnected: () {
      // 连接成功后刷新状态
      _checkRemoteConnection();
    });
  }

  /// 打开相机控制页面（已连接时）
  void _openCameraControl() {
    final apiService = _apiManager.getCurrentApiService();
    if (apiService != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CameraControlScreen(apiService: apiService),
        ),
      );
    }
  }

  /// 断开连接
  Future<void> _disconnect() async {
    try {
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

  /// 桌面布局：左侧导航栏 + 右侧内容 + 底部连接状态栏
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
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
          ),
          // 底部连接状态栏
          _buildConnectionStatusBar(),
        ],
      ),
    );
  }

  /// 移动端布局：内容 + 底部连接状态栏 + 底部导航栏
  Widget _buildMobileLayout() {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: _buildPageContent(),
          ),
          // 底部连接状态栏
          _buildConnectionStatusBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onNavigationChanged,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: '媒体库',
          ),
          const NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
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
              onPressed: _openConnectionDialog,
              icon: const Icon(Icons.link),
              label: const Text('连接远端相机'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部连接状态栏
  Widget _buildConnectionStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _isRemoteConnected 
            ? Colors.green.withOpacity(0.1) 
            : Colors.grey.withOpacity(0.1),
        border: Border(
          top: BorderSide(
            color: Colors.grey.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // 连接状态图标
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRemoteConnected ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 10),
          // 状态文字
          Expanded(
            child: Text(
              _isRemoteConnected 
                  ? '已连接 $_connectedHost' 
                  : '未连接远端服务',
              style: TextStyle(
                fontSize: 13,
                color: _isRemoteConnected ? Colors.green[700] : Colors.grey[600],
              ),
            ),
          ),
          // 操作按钮
          if (_isRemoteConnected) ...[
            // 拍摄按钮
            TextButton.icon(
              onPressed: _openCameraControl,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('拍摄'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            const SizedBox(width: 8),
            // 断开按钮
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('断开'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ] else ...[
            // 连接按钮
            TextButton.icon(
              onPressed: _openConnectionDialog,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('连接'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
