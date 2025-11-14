import 'package:flutter/material.dart';
import 'screens/device_connection_screen.dart';
import 'services/logger_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志系统（必须在最前面）
  final logger = ClientLoggerService();
  try {
    await logger.initialize();
    logger.log('应用启动', tag: 'INIT');
  } catch (e) {
    // 即使日志初始化失败，也要继续运行
    print('[MAIN] 日志系统初始化失败: $e');
  }
  
  runApp(const RemoteCamClientApp());
}

class RemoteCamClientApp extends StatelessWidget {
  const RemoteCamClientApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '远程相机控制',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const DeviceConnectionScreen(),
    );
  }
}
