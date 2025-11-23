import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/server_home_page.dart';
import 'services/logger_service.dart';
import 'services/version_compatibility_service.dart';
import 'services/update_service.dart';

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

  // 从 VERSION.yaml 初始化更新检查 URL（优先 Gitee，失败后 GitHub）
  await updateService.initializeUpdateUrls();

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
Future<void> _checkForUpdateOnStartup(
    UpdateService updateService, LoggerService logger) async {
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
            _showUpdateDialog(
                context, updateService, result.updateInfo!, logger);
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
    builder: (dialogContext) => _UpdateDialog(
      updateService: updateService,
      updateInfo: updateInfo,
      logger: logger,
    ),
  );
}

/// 更新对话框组件（支持下载进度显示）
class _UpdateDialog extends StatefulWidget {
  final UpdateService updateService;
  final dynamic updateInfo;
  final LoggerService logger;

  const _UpdateDialog({
    required this.updateService,
    required this.updateInfo,
    required this.logger,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;

  /// 将技术性错误转换为友好的中文提示
  String _getFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    // 404错误 - 文件不存在
    if (errorString.contains('404') || errorString.contains('not found')) {
      return '下载失败：更新文件不存在，请稍后重试或联系开发者';
    }

    // 网络连接错误
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('socket') ||
        errorString.contains('failed host lookup')) {
      return '下载失败：网络连接异常，请检查网络设置后重试';
    }

    // 权限错误
    if (errorString.contains('permission') ||
        errorString.contains('denied') ||
        errorString.contains('unauthorized')) {
      return '下载失败：存储权限不足，请在设置中授予存储权限';
    }

    // 磁盘空间不足
    if (errorString.contains('space') ||
        errorString.contains('disk') ||
        errorString.contains('storage')) {
      return '下载失败：存储空间不足，请清理空间后重试';
    }

    // 文件路径相关错误
    if (errorString.contains('path') ||
        errorString.contains('file') ||
        errorString.contains('directory')) {
      return '下载失败：无法保存文件，请检查存储权限';
    }

    // 服务器错误
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('server error')) {
      return '下载失败：服务器暂时不可用，请稍后重试';
    }

    // 其他错误 - 显示简化后的错误信息
    if (errorString.contains('dioexception')) {
      if (errorString.contains('bad response')) {
        return '下载失败：服务器响应异常，请稍后重试';
      }
      return '下载失败：网络请求异常，请检查网络连接';
    }

    // 默认错误提示
    return '下载失败：请检查网络连接后重试，如问题持续存在请联系开发者';
  }

  Future<void> _downloadAndOpen() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    try {
      widget.logger.log('开始下载更新文件', tag: 'UPDATE');

      final filePath = await widget.updateService.downloadUpdateFile(
        widget.updateInfo,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );

      if (filePath == null) {
        throw Exception('下载失败：文件路径为空');
      }

      widget.logger.log('下载完成，打开文件: $filePath', tag: 'UPDATE');

      // 关闭对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 打开文件
      final success = await widget.updateService.openDownloadedFile(filePath);
      if (!success) {
        final errorContext = navigatorKey.currentContext;
        if (errorContext != null && mounted) {
          ScaffoldMessenger.of(errorContext).showSnackBar(
            const SnackBar(
              content: Text('下载完成，但无法打开文件'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      widget.logger.logError('下载更新文件失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = _getFriendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本: ${widget.updateInfo.version}'),
            const SizedBox(height: 8),
            if (widget.updateInfo.releaseNotes != null) ...[
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.updateInfo.releaseNotes!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '文件: ${widget.updateInfo.fileName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              const Text('正在下载...',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_totalBytes > 0)
                LinearProgressIndicator(
                  value: _downloadedBytes / _totalBytes,
                ),
              if (_totalBytes > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${(_downloadedBytes / _totalBytes * 100).toStringAsFixed(1)}% '
                  '(${(_downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB / '
                  '${(_totalBytes / 1024 / 1024).toStringAsFixed(2)} MB)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.logger.log('用户取消更新', tag: 'UPDATE');
            },
            child: const Text('取消'),
          ),
        ElevatedButton(
          onPressed: _isDownloading ? null : _downloadAndOpen,
          child: Text(_isDownloading ? '下载中...' : '立即下载'),
        ),
      ],
    );
  }
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
