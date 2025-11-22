import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/update_info.dart';
import '../types/log_callbacks.dart';
import 'file_verification_service.dart';
import 'archive_service.dart';

/// 更新下载文件处理器
/// 负责处理下载完成的文件：hash校验、zip解压等
/// 客户端和服务端共享
class UpdateDownloadProcessor {
  /// 日志回调（可选）
  LogCallback? onLog;
  LogErrorCallback? onLogError;

  /// 文件校验服务
  final FileVerificationService _fileVerificationService;

  /// 归档服务
  final ArchiveService _archiveService;

  UpdateDownloadProcessor({
    this.onLog,
    this.onLogError,
    FileVerificationService? fileVerificationService,
    ArchiveService? archiveService,
  })  : _fileVerificationService = fileVerificationService ??
            FileVerificationService(
              onLog: (message, {tag}) =>
                  onLog?.call(message, tag: tag ?? 'VERIFY'),
              onLogError: (message, {error, stackTrace}) =>
                  onLogError?.call(message,
                      error: error, stackTrace: stackTrace),
            ),
        _archiveService = archiveService ??
            ArchiveService(
              onLog: (message, {tag}) =>
                  onLog?.call(message, tag: tag ?? 'ARCHIVE'),
              onLogError: (message, {error, stackTrace}) =>
                  onLogError?.call(message,
                      error: error, stackTrace: stackTrace),
            );

  /// 校验文件hash
  /// 
  /// [filePath] 文件路径
  /// [expectedHash] 期望的hash值
  /// 
  /// 返回true如果hash匹配，否则返回false
  Future<bool> verifyFileHash(String filePath, String expectedHash) async {
    return await _fileVerificationService.verifyFileHash(filePath, expectedHash);
  }

  /// 检查文件是否存在
  /// 
  /// [filePath] 文件路径
  /// 
  /// 返回文件大小（字节），如果文件不存在则返回null
  Future<int?> checkFileExists(String filePath) async {
    return await _fileVerificationService.checkFileExists(filePath);
  }

  /// 处理下载完成的文件（校验hash、解压等）
  /// 
  /// [filePath] 下载文件的路径
  /// [updateInfo] 更新信息
  /// [deleteZipAfterExtract] 解压后是否删除zip文件（默认true）
  /// 
  /// 返回处理后的文件路径（如果是zip则返回解压后的文件路径）
  Future<String?> processDownloadedFile(
    String filePath,
    UpdateInfo updateInfo, {
    bool deleteZipAfterExtract = true,
  }) async {
    try {
      // 如果有hash，进行校验
      if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
        onLog?.call('开始校验文件hash: $filePath', tag: 'UPDATE');
        final isValid = await _fileVerificationService.verifyFileHash(
            filePath, updateInfo.fileHash!);
        if (!isValid) {
          // 删除下载的文件
          try {
            await File(filePath).delete();
          } catch (e) {
            // 忽略删除错误
          }
          throw Exception('文件hash校验失败，下载的文件可能已损坏或被篡改');
        }
        onLog?.call('文件hash校验通过', tag: 'UPDATE');
      } else {
        onLog?.call('更新信息中未包含hash，跳过校验', tag: 'UPDATE');
      }

      // 如果是zip文件，先解压
      if (updateInfo.fileType.toLowerCase() == 'zip') {
        onLog?.call('检测到zip文件，开始解压', tag: 'UPDATE');
        final extractDir = path.join(path.dirname(filePath),
            'extracted_${path.basenameWithoutExtension(filePath)}');
        final extractedFilePath = await _archiveService.extractZipFile(
            filePath, extractDir);

        if (extractedFilePath == null) {
          // 如果找不到预期的安装文件，直接返回zip文件路径
          onLog?.call('未找到预期的安装文件，将打开zip文件本身: $filePath',
              tag: 'UPDATE');
          return filePath;
        }

        onLog?.call('zip文件解压完成: $extractedFilePath', tag: 'UPDATE');

        // 删除zip文件以节约空间（如果启用）
        if (deleteZipAfterExtract) {
          try {
            await File(filePath).delete();
            onLog?.call('已删除zip文件以节约空间: $filePath', tag: 'UPDATE');
          } catch (e) {
            onLog?.call('删除zip文件失败: $e', tag: 'UPDATE');
          }
        }

        // 返回解压后的文件路径
        return extractedFilePath;
      }

      return filePath;
    } catch (e, stackTrace) {
      onLogError?.call('处理下载文件失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}

