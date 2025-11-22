import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'logger_service.dart';

/// 下载目录管理服务
/// 统一管理下载目录的获取和操作
class DownloadDirectoryService {
  static final DownloadDirectoryService _instance = DownloadDirectoryService._internal();
  factory DownloadDirectoryService() => _instance;
  DownloadDirectoryService._internal();

  final ClientLoggerService _logger = ClientLoggerService();
  String? _cachedDownloadDir;

  /// 获取下载目录路径
  Future<String> getDownloadDirectory() async {
    if (_cachedDownloadDir != null) {
      return _cachedDownloadDir!;
    }

    try {
      String downloadDir;
      
      if (Platform.isAndroid) {
        // Android: 使用应用外部存储目录
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          downloadDir = path.join(directory.path, 'Downloads');
        } else {
          // 如果外部存储不可用，使用应用内部目录
          final appDir = await getApplicationDocumentsDirectory();
          downloadDir = path.join(appDir.path, 'Downloads');
        }
      } else if (Platform.isIOS) {
        // iOS: 使用应用文档目录
        final directory = await getApplicationDocumentsDirectory();
        downloadDir = path.join(directory.path, 'Downloads');
      } else if (Platform.isMacOS) {
        // macOS: 使用用户下载目录
        final directory = await getDownloadsDirectory();
        if (directory != null) {
          downloadDir = directory.path;
        } else {
          // 如果不可用，使用应用支持目录
          final appDir = await getApplicationSupportDirectory();
          downloadDir = path.join(appDir.path, 'Downloads');
        }
      } else if (Platform.isWindows) {
        // Windows: 使用用户下载目录
        final directory = await getDownloadsDirectory();
        if (directory != null) {
          downloadDir = directory.path;
        } else {
          // 如果不可用，使用应用数据目录
          final appDir = await getApplicationSupportDirectory();
          downloadDir = path.join(appDir.path, 'Downloads');
        }
      } else {
        // 其他平台：使用应用支持目录
        final appDir = await getApplicationSupportDirectory();
        downloadDir = path.join(appDir.path, 'Downloads');
      }

      // 确保目录存在
      await Directory(downloadDir).create(recursive: true);
      
      _cachedDownloadDir = downloadDir;
      _logger.log('下载目录: $downloadDir', tag: 'DOWNLOAD_DIR');
      return downloadDir;
    } catch (e, stackTrace) {
      _logger.logError('获取下载目录失败', error: e, stackTrace: stackTrace);
      // 返回默认目录
      final appDir = await getApplicationSupportDirectory();
      final defaultDir = path.join(appDir.path, 'Downloads');
      await Directory(defaultDir).create(recursive: true);
      return defaultDir;
    }
  }

  /// 清除缓存（用于重新获取目录）
  void clearCache() {
    _cachedDownloadDir = null;
  }
}

