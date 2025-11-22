import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/device_connection_screen.dart';
import 'services/logger_service.dart';
import 'services/api_service_manager.dart';
import 'services/update_service.dart';
import 'services/update_settings_service.dart';
import 'services/window_settings_service.dart';

// 全局导航键，用于在应用启动后显示对话框
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化窗口管理器（仅桌面平台）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await _initializeWindow();
  }
  
  // 初始化日志服务
  final logger = ClientLoggerService();
  await logger.initialize();
  
  // 初始化更新服务
  final updateService = UpdateService();
  final updateSettings = UpdateSettingsService();
  
  // 设置更新检查URL（如果未设置或使用旧的 GitLab URL）
  final updateCheckUrl = await updateSettings.getUpdateCheckUrl();
  const defaultUrl = 'https://raw.githubusercontent.com/shichao402/HelloKnightRemoteCam/main/update_config_github.json';
  
  if (updateCheckUrl.isEmpty || updateCheckUrl.contains('jihulab.com') || updateCheckUrl.contains('gitlab')) {
    // 如果未设置或使用旧的 GitLab URL，更新为新的 GitHub URL
    logger.log('更新检查URL为空或使用旧的GitLab URL，更新为GitHub URL', tag: 'UPDATE');
    await updateSettings.setUpdateCheckUrl(defaultUrl);
    updateService.setUpdateCheckUrl(defaultUrl);
  } else {
    updateService.setUpdateCheckUrl(updateCheckUrl);
  }
  
  // 启动应用
  runApp(const RemoteCamClientApp());
  
  // 应用启动后，独立检查更新（不阻塞启动，不依赖UI状态）
  // 等待一小段时间确保应用已完全启动
  Future.delayed(const Duration(milliseconds: 500), () {
    _checkForUpdateOnStartup(updateService, logger);
  });
}

/// 初始化窗口管理器
Future<void> _initializeWindow() async {
  await windowManager.ensureInitialized();
  
  const minSize = Size(800, 600);
  const defaultSize = Size(1200, 800);
  
  // 设置最小窗口尺寸
  await windowManager.setMinimumSize(minSize);
  
  // 获取保存的窗口设置
  final windowSettings = WindowSettingsService();
  final savedBounds = await windowSettings.getWindowBounds();
  
  // 如果有保存的设置，使用保存的位置和大小
  if (await windowSettings.hasWindowBounds()) {
    await windowManager.setSize(Size(savedBounds['width']!, savedBounds['height']!));
    if (savedBounds['x']! > 0 && savedBounds['y']! > 0) {
      await windowManager.setPosition(Offset(savedBounds['x']!, savedBounds['y']!));
    } else {
      await windowManager.center();
    }
  } else {
    // 否则使用默认设置
    await windowManager.setSize(defaultSize);
    await windowManager.center();
  }
  
  // 显示窗口
  await windowManager.show();
  await windowManager.focus();
}

/// 独立的更新检查逻辑，检查到更新后立即弹窗
Future<void> _checkForUpdateOnStartup(UpdateService updateService, ClientLoggerService logger) async {
  try {
    logger.log('启动时开始检查更新', tag: 'UPDATE');
    
    // 始终从网络检查更新
    final result = await updateService.checkForUpdate(avoidCache: true);
    
    if (result.hasUpdate && result.updateInfo != null) {
      logger.log('启动时发现新版本: ${result.updateInfo!.version}', tag: 'UPDATE');
      
      // 检查到更新后，立即弹窗提示
      final context = navigatorKey.currentContext;
      if (context != null) {
        _showUpdateDialog(context, updateService, result.updateInfo!, logger);
      } else {
        // 如果context还未准备好，等待一下再试
        Future.delayed(const Duration(milliseconds: 500), () {
          final context = navigatorKey.currentContext;
          if (context != null) {
            _showUpdateDialog(context, updateService, result.updateInfo!, logger);
          }
        });
      }
    } else {
      logger.log('启动时检查更新完成，当前已是最新版本', tag: 'UPDATE');
    }
  } catch (e, stackTrace) {
    logger.logError('启动时检查更新失败', error: e, stackTrace: stackTrace);
  }
}

/// 显示更新对话框
void _showUpdateDialog(BuildContext context, UpdateService updateService, 
    UpdateInfo updateInfo, ClientLoggerService logger) {
  updateService.showUpdateDialog(context, updateInfo);
}

class RemoteCamClientApp extends StatefulWidget {
  const RemoteCamClientApp({super.key});

  @override
  State<RemoteCamClientApp> createState() => _RemoteCamClientAppState();
}

class _RemoteCamClientAppState extends State<RemoteCamClientApp> 
    with WidgetsBindingObserver, WindowListener {
  final ClientLoggerService _logger = ClientLoggerService();
  final ApiServiceManager _apiServiceManager = ApiServiceManager();
  final WindowSettingsService _windowSettings = WindowSettingsService();

  @override
  void initState() {
    super.initState();
    // 注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);
    _logger.log('应用启动，已注册生命周期观察者', tag: 'LIFECYCLE');
    
    // 注册窗口监听器（仅桌面平台）
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    _logger.log('应用退出，已移除生命周期观察者', tag: 'LIFECYCLE');
    
    // 移除窗口监听器（仅桌面平台）
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    
    super.dispose();
  }
  
  // 窗口大小变化时保存
  @override
  void onWindowResize() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      
      await _windowSettings.saveWindowBounds(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
      );
    }
  }
  
  // 窗口移动时保存
  @override
  void onWindowMove() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      
      await _windowSettings.saveWindowBounds(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    _logger.log('应用生命周期状态变化: $state', tag: 'LIFECYCLE');
    
    switch (state) {
      case AppLifecycleState.resumed:
        // 应用恢复前台
        _logger.log('应用恢复前台', tag: 'LIFECYCLE');
        break;
        
      case AppLifecycleState.inactive:
        // 应用进入非活动状态（例如接电话、切换应用等）
        _logger.log('应用进入非活动状态', tag: 'LIFECYCLE');
        break;
        
      case AppLifecycleState.paused:
        // 应用进入后台
        _logger.log('应用进入后台', tag: 'LIFECYCLE');
        // 注意：在后台时，WebSocket连接通常仍然保持，不需要断开
        break;
        
      case AppLifecycleState.detached:
        // 应用即将终止（iOS上可能不会触发，macOS/Windows上会触发）
        _logger.log('应用即将终止，开始优雅关闭连接', tag: 'LIFECYCLE');
        _handleAppTermination();
        break;
        
      case AppLifecycleState.hidden:
        // 应用隐藏（某些平台可能不支持）
        _logger.log('应用隐藏', tag: 'LIFECYCLE');
        break;
    }
  }

  /// 处理应用终止
  /// 在应用退出前尝试优雅关闭连接
  Future<void> _handleAppTermination() async {
    try {
      _logger.log('开始处理应用终止，尝试优雅关闭连接', tag: 'LIFECYCLE');
      
      // 尝试优雅关闭连接
      // 注意：这里使用异步操作，但应用可能很快退出，所以不等待完成
      _apiServiceManager.gracefulDisconnect().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _logger.log('优雅关闭连接超时，强制断开', tag: 'LIFECYCLE');
        },
      ).catchError((e, stackTrace) {
        _logger.logError('优雅关闭连接失败', error: e, stackTrace: stackTrace);
      });
      
      // 给一点时间让关闭操作完成
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e, stackTrace) {
      _logger.logError('处理应用终止失败', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '远程相机客户端',
      debugShowCheckedModeBanner: true,
      navigatorKey: navigatorKey, // 使用全局导航键
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DeviceConnectionScreen(),
    );
  }
}
