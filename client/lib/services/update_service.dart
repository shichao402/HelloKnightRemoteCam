import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:shared/shared.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'file_download_service.dart';
import 'download_directory_service.dart';
import 'update_file_cleanup_service.dart';
import '../widgets/update_dialog.dart';

/// 更新服务
/// 负责检查更新、下载更新文件
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  final ClientLoggerService _logger = ClientLoggerService();
  final VersionService _versionService = VersionService();
  final Dio _dio = Dio();
  final FileDownloadService _fileDownloadService = FileDownloadService();
  final DownloadDirectoryService _downloadDirService =
      DownloadDirectoryService();
  final UpdateFileCleanupService _cleanupService = UpdateFileCleanupService();

  // 使用shared包的服务，注入logger回调
  late final UpdateCheckService _updateCheckService = UpdateCheckService(
    onLog: (message, {tag}) => _logger.log(message, tag: tag ?? 'UPDATE'),
    onLogError: (message, {error, stackTrace}) =>
        _logger.logError(message, error: error, stackTrace: stackTrace),
    dio: _dio,
  );

  late final UpdateDownloadProcessor _downloadProcessor =
      UpdateDownloadProcessor(
    onLog: (message, {tag}) => _logger.log(message, tag: tag ?? 'UPDATE'),
    onLogError: (message, {error, stackTrace}) =>
        _logger.logError(message, error: error, stackTrace: stackTrace),
  );

  // 默认更新检查URL（可以从设置中配置）
  String _updateCheckUrl = '';

  // 内存中的更新信息（不持久化）
  UpdateInfo? _currentUpdateInfo;

  /// 设置更新检查URL
  void setUpdateCheckUrl(String url) {
    _updateCheckUrl = url;
    _logger.log('设置更新检查URL: $url', tag: 'UPDATE');
  }

  /// 获取当前平台标识
  String _getCurrentPlatform() {
    if (Platform.isMacOS) {
      return 'macos';
    } else if (Platform.isWindows) {
      return 'windows';
    } else if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else if (Platform.isLinux) {
      return 'linux';
    } else {
      return 'unknown';
    }
  }

  /// 检查更新
  Future<UpdateCheckResult> checkForUpdate({bool avoidCache = true}) async {
    if (_updateCheckUrl.isEmpty) {
      return UpdateCheckResult(
        hasUpdate: false,
        error: '更新检查URL未设置',
      );
    }

    try {
      // 获取当前版本
      final currentVersion = await _versionService.getVersion();
      final currentVersionNumber = await _versionService.getVersionNumber();

      _logger.log('当前版本: $currentVersion', tag: 'UPDATE');

      // 使用shared包的UpdateCheckService检查更新
      final result = await _updateCheckService.checkForUpdate(
        updateCheckUrl: _updateCheckUrl,
        currentVersionNumber: currentVersionNumber,
        getPlatform: _getCurrentPlatform,
        target: 'client',
        avoidCache: avoidCache,
      );

      // 如果发现新版本，处理更新信息
      if (result.hasUpdate && result.updateInfo != null) {
        final updateInfo = result.updateInfo!;
        _logger.log('发现新版本: ${updateInfo.version}', tag: 'UPDATE');

        // 检查是否有旧的更新信息（内存中）
        if (_currentUpdateInfo != null &&
            _currentUpdateInfo!.version != updateInfo.version) {
          _logger.log(
              '检测到更新版本变更: ${_currentUpdateInfo!.version} -> ${updateInfo.version}',
              tag: 'UPDATE');
          // 清理旧的更新包
          await _cleanupOldUpdatePackages(_currentUpdateInfo!);
        }

        // 仅在内存中保存更新信息（不持久化）
        _currentUpdateInfo = updateInfo;
      } else {
        // 清除内存中的更新信息
        _currentUpdateInfo = null;
      }

      return result;
    } catch (e, stackTrace) {
      _logger.logError('检查更新失败', error: e, stackTrace: stackTrace);
      return UpdateCheckResult(
        hasUpdate: false,
        error: '检查更新失败: $e',
      );
    }
  }

  /// 获取保存的更新信息（从内存中获取，不持久化）
  Future<UpdateInfo?> getSavedUpdateInfo() async {
    return _currentUpdateInfo;
  }

  /// 检查是否有可用的更新（检查内存中的状态）
  Future<bool> hasUpdate() async {
    return _currentUpdateInfo != null;
  }


  /// 清理旧的更新包
  Future<void> _cleanupOldUpdatePackages(UpdateInfo oldUpdateInfo) async {
    try {
      _logger.log('开始清理旧的更新包: ${oldUpdateInfo.fileName}', tag: 'UPDATE');

      // 获取下载目录
      final downloadDir = await _downloadDirService.getDownloadDirectory();

      // 1. 删除旧的下载文件（已完成的）
      final oldFilePath = path.join(downloadDir, oldUpdateInfo.fileName);
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
          _logger.log('已删除旧的更新文件: $oldFilePath', tag: 'UPDATE');
        } catch (e) {
          _logger.log('删除旧更新文件失败: $e', tag: 'UPDATE');
        }
      }

      // 2. 删除未完成的下载文件（可能存在的部分下载）
      final partialFiles = await Directory(downloadDir)
          .list()
          .where((entity) =>
              entity is File && entity.path.contains(oldUpdateInfo.fileName))
          .cast<File>()
          .toList();

      for (final file in partialFiles) {
        try {
          await file.delete();
          _logger.log('已删除未完成的下载文件: ${file.path}', tag: 'UPDATE');
        } catch (e) {
          _logger.log('删除未完成文件失败: $e', tag: 'UPDATE');
        }
      }

      // 3. 删除旧的解压缓存目录
      final extractDirPattern =
          'extracted_${path.basenameWithoutExtension(oldUpdateInfo.fileName)}';
      final extractDir = path.join(downloadDir, extractDirPattern);
      final extractDirectory = Directory(extractDir);
      if (await extractDirectory.exists()) {
        try {
          await extractDirectory.delete(recursive: true);
          _logger.log('已删除旧的解压缓存: $extractDir', tag: 'UPDATE');
        } catch (e) {
          _logger.log('删除解压缓存失败: $e', tag: 'UPDATE');
        }
      }

      // 4. 清理所有解压缓存目录（以extracted_开头的目录）
      try {
        final downloadDirectory = Directory(downloadDir);
        if (await downloadDirectory.exists()) {
          await for (final entity in downloadDirectory.list()) {
            if (entity is Directory && entity.path.contains('extracted_')) {
              try {
                await entity.delete(recursive: true);
                _logger.log('已清理解压缓存: ${entity.path}', tag: 'UPDATE');
              } catch (e) {
                // 忽略删除错误
              }
            }
          }
        }
      } catch (e) {
        _logger.log('清理解压缓存时出错: $e', tag: 'UPDATE');
      }

      _logger.log('旧更新包清理完成', tag: 'UPDATE');
    } catch (e, stackTrace) {
      _logger.logError('清理旧更新包失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 清理旧版本文件（使用UpdateFileCleanupService）
  Future<void> _cleanupOldVersions() async {
    await _cleanupService.cleanupOldVersions();
  }

  /// 检查已存在的文件（已下载完成）
  /// 返回文件路径如果文件存在且hash校验通过，否则返回null
  Future<String?> _checkExistingCompleteFile(UpdateInfo updateInfo) async {
    try {
      final downloadDir = await _downloadDirService.getDownloadDirectory();
      final filePath = path.join(downloadDir, updateInfo.fileName);

      // 检查文件是否存在且大小合理（使用UpdateDownloadProcessor）
      final fileSize = await _downloadProcessor.checkFileExists(filePath);
      if (fileSize == null) {
        return null;
      }

      _logger.log('发现已存在的文件: $filePath (大小: $fileSize)', tag: 'UPDATE');

      // 如果有hash，验证文件完整性（使用UpdateDownloadProcessor）
      if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
        _logger.log('开始验证已存在文件的hash', tag: 'UPDATE');
        final isValid = await _downloadProcessor.verifyFileHash(
            filePath, updateInfo.fileHash!);
        if (isValid) {
          _logger.log('已存在文件hash校验通过: $filePath', tag: 'UPDATE');
          return filePath;
        } else {
          _logger.log('已存在文件hash校验失败，将重新下载', tag: 'UPDATE');
          // 删除损坏的文件
          try {
            await File(filePath).delete();
          } catch (e) {
            _logger.log('删除损坏文件失败: $e', tag: 'UPDATE');
          }
          return null;
        }
      } else {
        // 没有hash，假设文件完整
        _logger.log('更新信息中未包含hash，假设已存在文件完整: $filePath', tag: 'UPDATE');
        return filePath;
      }
    } catch (e, stackTrace) {
      _logger.logError('检查已存在文件失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 检查未下载完成的文件（支持断点续传）
  /// 返回文件路径如果文件存在且可以继续下载，否则返回null
  /// 注意：此方法不验证hash，hash验证在调用方进行
  Future<String?> _checkExistingIncompleteFile(UpdateInfo updateInfo) async {
    try {
      final downloadDir = await _downloadDirService.getDownloadDirectory();
      final filePath = path.join(downloadDir, updateInfo.fileName);

      // 检查文件是否存在（包括大小为0的文件，可以用于断点续传）
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final fileSize = await file.length();
      _logger.log('发现已存在的文件: $filePath (大小: $fileSize)', tag: 'UPDATE');

      // 文件存在，可以用于断点续传（hash验证在调用方进行）
      return filePath;
    } catch (e, stackTrace) {
      _logger.logError('检查未完成文件失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 下载更新文件
  ///
  /// [updateInfo] 更新信息
  /// [onProgress] 进度回调 (received, total)
  /// [onStatus] 状态回调，用于通知UI当前操作状态
  ///
  /// 返回下载文件的路径（如果是zip则返回解压后的文件路径）
  Future<String?> downloadUpdateFile(
    UpdateInfo updateInfo, {
    Function(int received, int total)? onProgress,
    Function(String status)? onStatus,
  }) async {
    try {
      _logger.log('开始下载更新文件: ${updateInfo.fileName}', tag: 'UPDATE');

      // 1. 清理旧版本文件
      onStatus?.call('正在清理旧版本文件...');
      await _cleanupOldVersions();

      // 2. 优先检查已下载完成的文件
      onStatus?.call('正在检查已下载的文件...');
      final existingCompleteFile = await _checkExistingCompleteFile(updateInfo);
      if (existingCompleteFile != null) {
        _logger.log('使用已下载完成的文件: $existingCompleteFile', tag: 'UPDATE');
        // 直接处理文件（hash校验、解压等）
        onStatus?.call('正在处理文件...');
        return await _processDownloadedFile(existingCompleteFile, updateInfo);
      }

      // 3. 检查未下载完成的文件（断点续传）
      onStatus?.call('正在检查未完成的下载...');
      final existingIncompleteFile =
          await _checkExistingIncompleteFile(updateInfo);
      String filePath;
      if (existingIncompleteFile != null) {
        // 检查文件是否实际已完成（通过hash验证，使用UpdateDownloadProcessor）
        if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
          onStatus?.call('正在校验文件完整性...');
          final isValid = await _downloadProcessor.verifyFileHash(
              existingIncompleteFile, updateInfo.fileHash!);
          if (isValid) {
            _logger.log('未完成文件实际已完整（hash校验通过），直接使用: $existingIncompleteFile',
                tag: 'UPDATE');
            return await _processDownloadedFile(
                existingIncompleteFile, updateInfo);
          }
        }
        _logger.log('发现未完成的下载文件，继续下载: $existingIncompleteFile', tag: 'UPDATE');
        onStatus?.call('准备断点续传...');
        filePath = existingIncompleteFile;
      } else {
        // 4. 开始新下载
        _logger.log('开始新下载', tag: 'UPDATE');
        onStatus?.call('准备开始下载...');
        filePath = await _fileDownloadService.downloadFile(
          url: updateInfo.downloadUrl,
          fileName: updateInfo.fileName,
          onProgress: onProgress,
          onStatus: onStatus,
        );
      }

      _logger.log('更新文件下载完成: $filePath', tag: 'UPDATE');

      // 处理下载完成的文件（校验hash、解压等）
      return await _processDownloadedFile(filePath, updateInfo);
    } catch (e, stackTrace) {
      _logger.logError('下载更新文件失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 处理下载完成的文件（校验hash、解压等）
  Future<String?> _processDownloadedFile(
      String filePath, UpdateInfo updateInfo) async {
    // 使用shared包的UpdateDownloadProcessor处理文件
    return await _downloadProcessor.processDownloadedFile(
      filePath,
      updateInfo,
      deleteZipAfterExtract: true,
    );
  }

  /// 打开下载的文件
  /// 根据平台和文件类型使用不同的打开方式
  Future<bool> openDownloadedFile(String filePath) async {
    try {
      _logger.log('打开下载的文件: $filePath', tag: 'UPDATE');

      final file = File(filePath);
      if (!await file.exists()) {
        _logger.logError('文件不存在', error: 'Path: $filePath');
        return false;
      }

      // 根据平台和文件类型选择打开方式
      if (Platform.isWindows) {
        // Windows: 直接打开exe或msi文件
        final ext = path.extension(filePath).toLowerCase();
        if (ext == '.exe' || ext == '.msi') {
          final result =
              await Process.run('start', ['', filePath], runInShell: true);
          if (result.exitCode == 0) {
            _logger.log('已打开Windows安装程序', tag: 'UPDATE');
            return true;
          }
        }
      } else if (Platform.isMacOS) {
        // macOS: 打开dmg文件
        final ext = path.extension(filePath).toLowerCase();
        if (ext == '.dmg') {
          final result = await Process.run('open', [filePath]);
          if (result.exitCode == 0) {
            _logger.log('已打开macOS DMG文件', tag: 'UPDATE');
            return true;
          }
        } else if (ext == '.app') {
          // 如果是app包，直接打开
          final result = await Process.run('open', [filePath]);
          if (result.exitCode == 0) {
            _logger.log('已打开macOS应用', tag: 'UPDATE');
            return true;
          }
        }
      } else if (Platform.isAndroid) {
        // Android: 使用系统安装程序打开apk
        final ext = path.extension(filePath).toLowerCase();
        if (ext == '.apk') {
          // Android需要使用Intent打开，这里使用open_file插件
          final result = await OpenFile.open(filePath);
          if (result.type == ResultType.done) {
            _logger.log('已打开Android APK安装程序', tag: 'UPDATE');
            return true;
          }
        }
      }

      // 默认使用open_file插件打开
      final result = await OpenFile.open(filePath);

      if (result.type == ResultType.done) {
        _logger.log('已打开文件', tag: 'UPDATE');
        return true;
      } else {
        _logger.logError('打开文件失败',
            error: 'Result: ${result.type}, Message: ${result.message}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.logError('打开文件失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 显示更新对话框
  /// 这是统一的更新UI入口，所有地方都应该使用这个方法
  void showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
    UpdateDialog.show(
      context,
      updateService: this,
      updateInfo: updateInfo,
      logger: _logger,
    );
  }
}
