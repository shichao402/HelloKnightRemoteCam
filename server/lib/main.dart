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
  
  // 启动时自动检查更新（后台执行，不阻塞启动）
  updateService.checkForUpdate(avoidCache: true).then((result) {
    if (result.hasUpdate && result.updateInfo != null) {
      logger.log('启动时发现新版本: ${result.updateInfo!.version}', tag: 'UPDATE');
    } else {
      logger.log('启动时检查更新完成，当前已是最新版本', tag: 'UPDATE');
    }
  }).catchError((e) {
    logger.logError('启动时检查更新失败', error: e);
  });
  
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

