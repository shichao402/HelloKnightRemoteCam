import 'package:flutter/material.dart';
import 'screens/device_connection_screen.dart';
import 'services/logger_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志服务
  final logger = ClientLoggerService();
  logger.initialize();
  
  runApp(const RemoteCamClientApp());
}

class RemoteCamClientApp extends StatelessWidget {
  const RemoteCamClientApp({super.key});

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
