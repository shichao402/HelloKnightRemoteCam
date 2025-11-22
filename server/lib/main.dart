import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/server_home_page.dart';
import 'services/logger_service.dart';
import 'services/version_compatibility_service.dart';
import 'services/update_service.dart';
import 'services/update_settings_service.dart';

List<CameraDescription> cameras = [];

// 全局导航键，用于在应用启动后显示对话框
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    logger.logError('获取相机列表失败', error: e);
  }
  
  // 启动应用
  runApp(const RemoteCamServerApp());
  
  // 应用启动后，独立检查更新（不阻塞启动，不依赖UI状态）
  // 等待一小段时间确保应用已完全启动
  Future.delayed(const Duration(milliseconds: 500), () {
    _checkForUpdateOnStartup(updateService, logger);
  });
}

/// 独立的更新检查逻辑，检查到更新后立即弹窗
Future<void> _checkForUpdateOnStartup(UpdateService updateService, LoggerService logger) async {
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
    dynamic updateInfo, LoggerService logger) {
  showDialog(
    context: context,
    barrierDismissible: false, // 不允许点击外部关闭
    builder: (context) => AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本: ${updateInfo.version}'),
            const SizedBox(height: 8),
            if (updateInfo.releaseNotes != null) ...[
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                updateInfo.releaseNotes!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '文件: ${updateInfo.fileName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            logger.log('用户取消更新', tag: 'UPDATE');
          },
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            logger.log('用户确认更新，打开下载链接', tag: 'UPDATE');
            final success = await updateService.openDownloadUrl(updateInfo.downloadUrl);
            if (!success) {
              // 如果无法打开链接，再次显示错误提示
              final errorContext = navigatorKey.currentContext;
              if (errorContext != null) {
                ScaffoldMessenger.of(errorContext).showSnackBar(
                  const SnackBar(
                    content: Text('无法打开下载链接'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
          },
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
}

class RemoteCamServerApp extends StatelessWidget {
  const RemoteCamServerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '远程相机服务端',
      navigatorKey: navigatorKey, // 使用全局导航键
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ServerHomePage(),
    );
  }
}

