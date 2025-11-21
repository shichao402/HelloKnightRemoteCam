import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/server_home_page.dart';
import 'services/logger_service.dart';
import 'services/version_compatibility_service.dart';
import 'services/update_service.dart';
import 'services/update_settings_service.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final logger = LoggerService();
  await logger.initialize();
  
  // 初始化版本兼容性服务
  final versionCompatibilityService = VersionCompatibilityService();
  await versionCompatibilityService.initialize();
  
  // 初始化更新服务
  final updateService = UpdateService();
  final updateSettings = UpdateSettingsService();
  
  // 设置更新检查URL（如果未设置）
  final updateCheckUrl = await updateSettings.getUpdateCheckUrl();
  if (updateCheckUrl.isEmpty) {
    // 设置默认更新检查URL
    const defaultUrl = 'https://jihulab.com/api/v4/projects/298216/repository/files/update_config.json/raw?ref=main';
    await updateSettings.setUpdateCheckUrl(defaultUrl);
    updateService.setUpdateCheckUrl(defaultUrl);
  } else {
    updateService.setUpdateCheckUrl(updateCheckUrl);
  }
  
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

