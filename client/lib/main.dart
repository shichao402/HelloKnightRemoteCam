import 'package:flutter/material.dart';
import 'screens/device_connection_screen.dart';
import 'services/logger_service.dart';
import 'services/api_service_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志服务
  final logger = ClientLoggerService();
  logger.initialize();
  
  runApp(const RemoteCamClientApp());
}

class RemoteCamClientApp extends StatefulWidget {
  const RemoteCamClientApp({super.key});

  @override
  State<RemoteCamClientApp> createState() => _RemoteCamClientAppState();
}

class _RemoteCamClientAppState extends State<RemoteCamClientApp> with WidgetsBindingObserver {
  final ClientLoggerService _logger = ClientLoggerService();
  final ApiServiceManager _apiServiceManager = ApiServiceManager();

  @override
  void initState() {
    super.initState();
    // 注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);
    _logger.log('应用启动，已注册生命周期观察者', tag: 'LIFECYCLE');
  }

  @override
  void dispose() {
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    _logger.log('应用退出，已移除生命周期观察者', tag: 'LIFECYCLE');
    super.dispose();
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const DeviceConnectionScreen(),
    );
  }
}
