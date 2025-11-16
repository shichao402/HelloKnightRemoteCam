import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/server_home_page.dart';
import 'services/logger_service.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final logger = LoggerService();
  await logger.initialize();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    logger.logError('获取相机列表失败', error: e);
  }
  
  runApp(const RemoteCamServerApp());
}

class RemoteCamServerApp extends StatelessWidget {
  const RemoteCamServerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '远程相机服务端',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ServerHomePage(),
    );
  }
}

