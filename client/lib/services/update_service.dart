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

  // 更新检查 URL 列表（优先从 VERSION.yaml 读取）
  List<String> _updateCheckUrls = [];

  // 内存中的更新信息（不持久化）
  UpdateInfo? _currentUpdateInfo;

  /// 初始化更新检查 URL（从 VERSION.yaml 读取）
  Future<void> initializeUpdateUrls() async {
    try {
      _updateCheckUrls = await UpdateUrlConfigService.getUpdateCheckUrls();
      if (_updateCheckUrls.isNotEmpty) {
        _logger.log('从 VERSION.yaml 读取更新检查 URL: ${_updateCheckUrls.length} 个',
            tag: 'UPDATE');
        for (int i = 0; i < _updateCheckUrls.length; i++) {
          final source = i == 0 ? 'Gitee' : 'GitHub';
          _logger.log('  $source: ${_updateCheckUrls[i]}', tag: 'UPDATE');
        }
      } else {
        _logger.log('VERSION.yaml 中未找到更新检查 URL 配置', tag: 'UPDATE');
      }
    } catch (e, stackTrace) {
      _logger.logError('读取更新检查 URL 配置失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 设置更新检查URL（向后兼容，单个 URL）
  @Deprecated('使用 initializeUpdateUrls 从 VERSION.yaml 读取')
  void setUpdateCheckUrl(String url) {
    _updateCheckUrls = [url];
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
    // 如果 URL 列表为空，尝试初始化
    if (_updateCheckUrls.isEmpty) {
      await initializeUpdateUrls();
    }

    if (_updateCheckUrls.isEmpty) {
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
      _logger.log('当前版本号(不含构建号): $currentVersionNumber', tag: 'UPDATE');
      _logger.log('当前平台: ${_getCurrentPlatform()}', tag: 'UPDATE');
      _logger.log('更新检查 URL 列表 (共 ${_updateCheckUrls.length} 个，将并行检查):',
          tag: 'UPDATE');
      for (int i = 0; i < _updateCheckUrls.length; i++) {
        final url = _updateCheckUrls[i];
        final sourceName = url.contains('gitee.com') ? 'Gitee' : 'GitHub';
        _logger.log('  ${i + 1}. $sourceName: $url', tag: 'UPDATE');
      }
      _logger.log('开始并行检查所有更新源...', tag: 'UPDATE');

      // 使用shared包的UpdateCheckService检查更新（支持多个 URL）
      final result = await _updateCheckService.checkForUpdate(
        updateCheckUrls: _updateCheckUrls,
        currentVersionNumber: currentVersionNumber,
        getPlatform: _getCurrentPlatform,
        target: 'client',
        avoidCache: avoidCache,
      );

      // 如果发现新版本，处理更新信息
      if (result.hasUpdate && result.updateInfo != null) {
        final updateInfo = result.updateInfo!;

        // 判断下载来源（从 downloadUrl 判断）
        String downloadSource = 'Unknown';
        if (updateInfo.downloadUrl.contains('gitee.com')) {
          downloadSource = 'Gitee';
        } else if (updateInfo.downloadUrl.contains('github.com')) {
          downloadSource = 'GitHub';
        }

        _logger.log('发现新版本: ${updateInfo.version}', tag: 'UPDATE');
        _logger.log('最终选择的下载源: $downloadSource', tag: 'UPDATE');
        _logger.log('更新信息已保存到内存:', tag: 'UPDATE');
        _logger.log('  版本号: ${updateInfo.version}', tag: 'UPDATE');
        _logger.log('  版本号(不含构建号): ${updateInfo.versionNumber}', tag: 'UPDATE');
        _logger.log('  下载 URL: ${updateInfo.downloadUrl}', tag: 'UPDATE');
        _logger.log('  下载来源: $downloadSource', tag: 'UPDATE');
        _logger.log('  文件名: ${updateInfo.fileName}', tag: 'UPDATE');
        _logger.log('  文件类型: ${updateInfo.fileType}', tag: 'UPDATE');
        _logger.log('  平台: ${updateInfo.platform}', tag: 'UPDATE');
        if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
          _logger.log('  文件 Hash: ${updateInfo.fileHash}', tag: 'UPDATE');
        } else {
          _logger.log('  文件 Hash: 未提供', tag: 'UPDATE');
        }

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

  /// 公开的清理旧版本文件方法（供外部调用，如启动时清理）
  Future<void> cleanupOldVersions() async {
    await _cleanupService.cleanupOldVersions();
  }

  /// 检查已存在的文件（已下载完成）
  /// 只检查 zip 文件，如果存在且 hash 校验通过，返回文件路径（将重新解压）
  /// 如果文件不存在或 hash 校验失败，返回 null
  Future<String?> _checkExistingCompleteFile(UpdateInfo updateInfo) async {
    try {
      final downloadDir = await _downloadDirService.getDownloadDirectory();
      final filePath = path.join(downloadDir, updateInfo.fileName);

      // 检查 zip 文件是否存在
      final fileSize = await _downloadProcessor.checkFileExists(filePath);
      if (fileSize == null) {
        _logger.log('zip 文件不存在: $filePath', tag: 'UPDATE');
        return null;
      }

      _logger.log('发现已存在的 zip 文件: $filePath (大小: $fileSize)', tag: 'UPDATE');

      // 如果有hash，验证文件完整性（使用UpdateDownloadProcessor）
      if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
        _logger.log('开始验证已存在 zip 文件的hash', tag: 'UPDATE');
        final isValid = await _downloadProcessor.verifyFileHash(
            filePath, updateInfo.fileHash!);
        if (isValid) {
          _logger.log('已存在 zip 文件hash校验通过: $filePath', tag: 'UPDATE');
          _logger.log('将重新解压 zip 文件', tag: 'UPDATE');
          return filePath;
        } else {
          _logger.log('已存在 zip 文件hash校验失败，将重新下载', tag: 'UPDATE');
          // 删除损坏的文件
          try {
            await File(filePath).delete();
            _logger.log('已删除损坏的 zip 文件', tag: 'UPDATE');
          } catch (e) {
            _logger.log('删除损坏文件失败: $e', tag: 'UPDATE');
          }
          return null;
        }
      } else {
        // 没有hash，假设文件完整
        _logger.log('更新信息中未包含hash，假设已存在 zip 文件完整: $filePath', tag: 'UPDATE');
        _logger.log('将重新解压 zip 文件', tag: 'UPDATE');
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
    // 使用局部变量存储当前使用的 updateInfo（可能被 fallback 替换）
    UpdateInfo currentUpdateInfo = updateInfo;

    try {
      // 1. 清理旧版本文件
      onStatus?.call('正在清理旧版本文件...');
      await _cleanupOldVersions();

      // 2. 优先检查已下载完成的文件
      onStatus?.call('正在检查已下载的文件...');
      final existingCompleteFile =
          await _checkExistingCompleteFile(currentUpdateInfo);
      if (existingCompleteFile != null) {
        _logger.log('使用已下载完成的文件: $existingCompleteFile', tag: 'UPDATE');
        // 直接处理文件（hash校验、解压等）
        onStatus?.call('正在处理文件...');
        return await _processDownloadedFile(
            existingCompleteFile, currentUpdateInfo);
      }

      // 3. 检查未下载完成的文件（断点续传）
      onStatus?.call('正在检查未完成的下载...');
      final existingIncompleteFile =
          await _checkExistingIncompleteFile(currentUpdateInfo);
      String filePath;
      if (existingIncompleteFile != null) {
        // 检查文件是否实际已完成（通过hash验证，使用UpdateDownloadProcessor）
        if (currentUpdateInfo.fileHash != null &&
            currentUpdateInfo.fileHash!.isNotEmpty) {
          onStatus?.call('正在校验文件完整性...');
          final isValid = await _downloadProcessor.verifyFileHash(
              existingIncompleteFile, currentUpdateInfo.fileHash!);
          if (isValid) {
            _logger.log('未完成文件实际已完整（hash校验通过），直接使用: $existingIncompleteFile',
                tag: 'UPDATE');
            return await _processDownloadedFile(
                existingIncompleteFile, currentUpdateInfo);
          }
        }
        _logger.log('发现未完成的下载文件，继续下载: $existingIncompleteFile', tag: 'UPDATE');
        onStatus?.call('准备断点续传...');
        filePath = existingIncompleteFile;
      } else {
        // 4. 开始新下载（带 fallback 逻辑）
        _logger.log('开始新下载', tag: 'UPDATE');
        onStatus?.call('准备开始下载...');

        // 尝试下载，如果失败且是 Gitee URL，则 fallback 到 GitHub
        try {
          filePath = await _fileDownloadService.downloadFile(
            url: currentUpdateInfo.downloadUrl,
            fileName: currentUpdateInfo.fileName,
            onProgress: onProgress,
            onStatus: onStatus,
          );
        } catch (e, _) {
          // 如果下载失败且当前 URL 是 Gitee，尝试 fallback 到 GitHub
          if (currentUpdateInfo.downloadUrl.contains('gitee.com')) {
            _logger.log('Gitee 下载失败，尝试从 GitHub fallback', tag: 'UPDATE');
            onStatus?.call('Gitee 下载失败，尝试从 GitHub 下载...');

            // 尝试从 GitHub 配置获取 downloadUrl
            try {
              final githubUpdateInfo =
                  await _getGitHubUpdateInfo(currentUpdateInfo);
              if (githubUpdateInfo != null) {
                _logger.log(
                    '从 GitHub 获取到更新信息，使用 GitHub downloadUrl: ${githubUpdateInfo.downloadUrl}',
                    tag: 'UPDATE');
                _logger.log('GitHub 期望 hash: ${githubUpdateInfo.fileHash}',
                    tag: 'UPDATE');
                filePath = await _fileDownloadService.downloadFile(
                  url: githubUpdateInfo.downloadUrl,
                  fileName: githubUpdateInfo.fileName,
                  onProgress: onProgress,
                  onStatus: onStatus,
                );
                // 使用 GitHub 的 updateInfo（包含正确的 hash）
                currentUpdateInfo = githubUpdateInfo;
              } else {
                // GitHub 也获取失败，抛出原始错误
                rethrow;
              }
            } catch (fallbackError, fallbackStackTrace) {
              _logger.logError('GitHub fallback 也失败',
                  error: fallbackError, stackTrace: fallbackStackTrace);
              rethrow; // 抛出原始错误
            }
          } else {
            // 不是 Gitee URL，直接抛出错误
            rethrow;
          }
        }
      }

      _logger.log('更新文件下载完成: $filePath', tag: 'UPDATE');
      _logger.log('准备处理下载文件:', tag: 'UPDATE');
      _logger.log('  文件路径: $filePath', tag: 'UPDATE');
      _logger.log('  版本: ${currentUpdateInfo.version}', tag: 'UPDATE');
      _logger.log('  文件名: ${currentUpdateInfo.fileName}', tag: 'UPDATE');
      if (currentUpdateInfo.fileHash != null &&
          currentUpdateInfo.fileHash!.isNotEmpty) {
        _logger.log('  期望 Hash: ${currentUpdateInfo.fileHash}', tag: 'UPDATE');
      }

      // 处理下载完成的文件（校验hash、解压等）
      return await _processDownloadedFile(filePath, currentUpdateInfo);
    } catch (e, stackTrace) {
      _logger.logError('下载更新文件失败', error: e, stackTrace: stackTrace);
      // 如果所有 fallback 都失败，抛出错误
      rethrow;
    }
  }

  /// 从 GitHub 获取更新信息（用于 fallback）
  Future<UpdateInfo?> _getGitHubUpdateInfo(UpdateInfo currentUpdateInfo) async {
    try {
      _logger.log('开始从 GitHub 获取更新信息（fallback）', tag: 'UPDATE');
      _logger.log('当前更新信息:', tag: 'UPDATE');
      _logger.log('  版本: ${currentUpdateInfo.version}', tag: 'UPDATE');
      _logger.log('  下载 URL: ${currentUpdateInfo.downloadUrl}', tag: 'UPDATE');
      _logger.log('  文件名: ${currentUpdateInfo.fileName}', tag: 'UPDATE');

      // 确保 URL 列表已初始化
      if (_updateCheckUrls.isEmpty) {
        await initializeUpdateUrls();
      }

      // 找到 GitHub URL（通常是第二个）
      String? githubUrl;
      for (int i = 0; i < _updateCheckUrls.length; i++) {
        if (_updateCheckUrls[i].contains('github.com')) {
          githubUrl = _updateCheckUrls[i];
          break;
        }
      }

      if (githubUrl == null || githubUrl.isEmpty) {
        _logger.log('未找到 GitHub 更新检查 URL', tag: 'UPDATE');
        return null;
      }

      _logger.log('使用 GitHub 更新检查 URL: $githubUrl', tag: 'UPDATE');

      // 获取当前版本号
      final currentVersionNumber = await _versionService.getVersionNumber();

      // 使用 UpdateCheckService 从 GitHub 获取更新信息
      final result = await _updateCheckService.checkForUpdate(
        updateCheckUrls: [githubUrl],
        currentVersionNumber: currentVersionNumber,
        getPlatform: _getCurrentPlatform,
        target: 'client',
        avoidCache: true,
      );

      if (result.hasUpdate && result.updateInfo != null) {
        final githubUpdateInfo = result.updateInfo!;
        _logger.log('从 GitHub 获取到更新信息:', tag: 'UPDATE');
        _logger.log('  版本: ${githubUpdateInfo.version}', tag: 'UPDATE');
        _logger.log('  下载 URL: ${githubUpdateInfo.downloadUrl}', tag: 'UPDATE');
        _logger.log('  文件名: ${githubUpdateInfo.fileName}', tag: 'UPDATE');
        if (githubUpdateInfo.fileHash != null &&
            githubUpdateInfo.fileHash!.isNotEmpty) {
          _logger.log('  文件 Hash: ${githubUpdateInfo.fileHash}', tag: 'UPDATE');
        }

        // 确保版本号匹配
        if (githubUpdateInfo.version == currentUpdateInfo.version) {
          _logger.log('版本号匹配，可以使用 GitHub 的更新信息', tag: 'UPDATE');
          return githubUpdateInfo;
        } else {
          _logger.log(
              '版本号不匹配: GitHub ${githubUpdateInfo.version} != 当前 ${currentUpdateInfo.version}',
              tag: 'UPDATE');
          return null;
        }
      } else {
        _logger.log('GitHub 未找到更新信息', tag: 'UPDATE');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.logError('从 GitHub 获取更新信息失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 处理下载完成的文件（校验hash、解压等）
  Future<String?> _processDownloadedFile(
      String filePath, UpdateInfo updateInfo) async {
    // 使用shared包的UpdateDownloadProcessor处理文件
    // 不删除 zip 文件，保留以便后续可以重新解压
    return await _downloadProcessor.processDownloadedFile(
      filePath,
      updateInfo,
      deleteZipAfterExtract: false,
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
