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
  /// 使用应用专属子目录，避免与其他应用冲突
  Future<String> getDownloadDirectory() async {
    if (_cachedDownloadDir != null) {
      return _cachedDownloadDir!;
    }

    try {
      // 使用系统临时目录作为基础目录
      final tempDir = await getTemporaryDirectory();
      // 创建应用专属子目录：com.example.remoteCamClient
      // Updates 目录用于存放更新文件（与用户下载目录区分）
      final downloadDir = path.join(tempDir.path, 'com.example.remoteCamClient', 'Updates');

      // 确保目录存在
      await Directory(downloadDir).create(recursive: true);
      
      _cachedDownloadDir = downloadDir;
      _logger.log('下载目录: $downloadDir', tag: 'DOWNLOAD_DIR');
      return downloadDir;
    } catch (e, stackTrace) {
      _logger.logError('获取下载目录失败', error: e, stackTrace: stackTrace);
      // 返回默认目录（系统临时目录下的应用专属目录）
      final tempDir = await getTemporaryDirectory();
      final defaultDir = path.join(tempDir.path, 'com.example.remoteCamClient', 'Updates');
      await Directory(defaultDir).create(recursive: true);
      return defaultDir;
    }
  }

  /// 清除缓存（用于重新获取目录）
  void clearCache() {
    _cachedDownloadDir = null;
  }
}

