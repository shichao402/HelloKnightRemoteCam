import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared/shared.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'download_directory_service.dart';

/// 更新文件清理服务
/// 负责清理旧版本的更新文件
class UpdateFileCleanupService {
  static final UpdateFileCleanupService _instance = UpdateFileCleanupService._internal();
  factory UpdateFileCleanupService() => _instance;
  UpdateFileCleanupService._internal();

  final ClientLoggerService _logger = ClientLoggerService();
  final VersionService _versionService = VersionService();
  final DownloadDirectoryService _downloadDirService = DownloadDirectoryService();

  /// 从文件名提取版本号（使用shared包的VersionUtils）
  String? _extractVersionFromFileName(String fileName) {
    try {
      return VersionUtils.extractVersionFromFileName(fileName);
    } catch (e) {
      _logger.log('从文件名提取版本号失败: $fileName, 错误: $e', tag: 'CLEANUP');
      return null;
    }
  }

  /// 清理旧版本文件（清理所有<=当前版本的文件）
  Future<void> cleanupOldVersions() async {
    try {
      final currentVersion = await _versionService.getVersion();
      _logger.log('开始清理旧版本文件，当前版本: $currentVersion', tag: 'CLEANUP');

      final downloadDir = await _downloadDirService.getDownloadDirectory();
      final dir = Directory(downloadDir);

      if (!await dir.exists()) {
        _logger.log('下载目录不存在，跳过清理', tag: 'CLEANUP');
        return;
      }

      final files = await dir.list().toList();
      int cleanedCount = 0;

      for (final fileEntity in files) {
        if (fileEntity is File) {
          final fileName = path.basename(fileEntity.path);
          final fileVersion = _extractVersionFromFileName(fileName);

          if (fileVersion != null) {
            // 比较版本，如果文件版本 <= 当前版本，则删除（使用shared包的VersionUtils）
            if (!VersionUtils.compareFullVersions(fileVersion, currentVersion) ||
                fileVersion == currentVersion) {
              try {
                await fileEntity.delete();
                _logger.log('已删除旧版本文件: $fileName (版本: $fileVersion)',
                    tag: 'CLEANUP');
                cleanedCount++;

                // 同时删除对应的解压目录（如果存在）
                final extractDir = path.join(path.dirname(fileEntity.path),
                    'extracted_${path.basenameWithoutExtension(fileName)}');
                final extractDirEntity = Directory(extractDir);
                if (await extractDirEntity.exists()) {
                  await extractDirEntity.delete(recursive: true);
                  _logger.log('已删除解压目录: $extractDir', tag: 'CLEANUP');
                }
              } catch (e) {
                _logger.log('删除文件失败: $fileName, 错误: $e', tag: 'CLEANUP');
              }
            }
          }
        }
      }

      _logger.log('旧版本文件清理完成，共清理 $cleanedCount 个文件', tag: 'CLEANUP');
    } catch (e, stackTrace) {
      _logger.logError('清理旧版本文件失败', error: e, stackTrace: stackTrace);
    }
  }
}

