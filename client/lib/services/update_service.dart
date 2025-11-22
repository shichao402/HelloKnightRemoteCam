import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'file_download_service.dart';
import '../widgets/update_dialog.dart';

/// 更新信息模型
class UpdateInfo {
  final String version;
  final String versionNumber;
  final String downloadUrl;
  final String fileName;
  final String fileType;
  final String platform;
  final String? releaseNotes;
  final String? fileHash; // SHA256 hash值

  UpdateInfo({
    required this.version,
    required this.versionNumber,
    required this.downloadUrl,
    required this.fileName,
    required this.fileType,
    required this.platform,
    this.releaseNotes,
    this.fileHash,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String,
      versionNumber: json['versionNumber'] as String,
      downloadUrl: json['downloadUrl'] as String,
      fileName: json['fileName'] as String,
      fileType: json['fileType'] as String,
      platform: json['platform'] as String,
      releaseNotes: json['releaseNotes'] as String?,
      fileHash: json['fileHash'] as String?,
    );
  }
}

/// 更新检查结果
class UpdateCheckResult {
  final bool hasUpdate;
  final UpdateInfo? updateInfo;
  final String? error;

  UpdateCheckResult({
    required this.hasUpdate,
    this.updateInfo,
    this.error,
  });
}

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

  /// 比较版本号
  /// 返回 true 如果 version1 > version2
  bool _compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((e) => int.parse(e)).toList();
    final v2Parts = version2.split('.').map((e) => int.parse(e)).toList();

    // 确保两个版本号都有3个部分
    while (v1Parts.length < 3) {
      v1Parts.add(0);
    }
    while (v2Parts.length < 3) {
      v2Parts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (v1Parts[i] > v2Parts[i]) return true;
      if (v1Parts[i] < v2Parts[i]) return false;
    }

    return false; // 相等
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
      // 添加时间戳参数避免缓存
      String url = _updateCheckUrl;
      if (avoidCache) {
        final uri = Uri.parse(url);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        url = uri.replace(queryParameters: {
          ...uri.queryParameters,
          '_t': timestamp.toString(),
        }).toString();
      }

      _logger.log('开始检查更新，URL: $url', tag: 'UPDATE');

      // 获取更新配置
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      if (response.statusCode != 200) {
        _logger.logError('更新检查失败', error: 'HTTP ${response.statusCode}');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '更新检查失败: HTTP ${response.statusCode}',
        );
      }

      // 处理响应数据：可能是 Map 或 String
      Map<String, dynamic> config;
      if (response.data is Map) {
        config = response.data as Map<String, dynamic>;
      } else if (response.data is String) {
        // 如果是字符串，需要手动解析 JSON
        config = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else {
        _logger.logError('更新检查失败',
            error: '响应数据格式不正确: ${response.data.runtimeType}');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '响应数据格式不正确',
        );
      }

      // 获取当前版本
      final currentVersion = await _versionService.getVersion();
      final currentVersionNumber = await _versionService.getVersionNumber();

      _logger.log('当前版本: $currentVersion', tag: 'UPDATE');

      // 获取当前平台
      final platform = _getCurrentPlatform();
      _logger.log('当前平台: $platform', tag: 'UPDATE');

      // 从配置中获取客户端更新信息
      final clientConfig = config['client'] as Map<String, dynamic>?;
      if (clientConfig == null) {
        _logger.log('配置中未找到客户端信息', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '配置中未找到客户端信息',
        );
      }

      // 获取平台特定的更新信息
      final platforms = clientConfig['platforms'] as Map<String, dynamic>?;
      if (platforms == null) {
        _logger.log('配置中未找到平台信息', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '配置中未找到平台信息',
        );
      }

      final platformConfig = platforms[platform] as Map<String, dynamic>?;
      if (platformConfig == null) {
        _logger.log('配置中未找到平台 $platform 的信息', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '配置中未找到平台 $platform 的信息',
        );
      }

      // 解析更新信息
      final updateInfo = UpdateInfo.fromJson(platformConfig);
      _logger.log('最新版本: ${updateInfo.version}', tag: 'UPDATE');

      // 比较版本
      final hasUpdate =
          _compareVersions(updateInfo.versionNumber, currentVersionNumber);

      if (hasUpdate) {
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
        return UpdateCheckResult(
          hasUpdate: true,
          updateInfo: updateInfo,
        );
      } else {
        _logger.log('当前已是最新版本', tag: 'UPDATE');
        // 清除内存中的更新信息
        _currentUpdateInfo = null;
        return UpdateCheckResult(
          hasUpdate: false,
        );
      }
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

  /// 计算文件的SHA256 hash
  Future<String> _calculateFileHash(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 校验文件hash
  Future<bool> verifyFileHash(String filePath, String expectedHash) async {
    try {
      _logger.log('开始校验文件hash: $filePath', tag: 'UPDATE');
      final actualHash = await _calculateFileHash(filePath);
      final isValid = actualHash.toLowerCase() == expectedHash.toLowerCase();

      if (isValid) {
        _logger.log('文件hash校验通过', tag: 'UPDATE');
      } else {
        _logger.logError('文件hash校验失败',
            error: '期望: $expectedHash, 实际: $actualHash');
      }

      return isValid;
    } catch (e, stackTrace) {
      _logger.logError('校验文件hash失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 解压zip文件
  Future<String?> _extractZipFile(String zipPath, String extractDir) async {
    try {
      _logger.log('开始解压zip文件: $zipPath', tag: 'UPDATE');

      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 创建解压目录
      final extractDirectory = Directory(extractDir);
      if (!await extractDirectory.exists()) {
        await extractDirectory.create(recursive: true);
      }

      // 解压所有文件
      String? extractedFilePath;
      String? apkFilePath; // 优先查找APK文件（Android）
      String? dmgFilePath; // 查找DMG文件（macOS）- GitHub Actions打包的zip中包含dmg
      String? exeFilePath; // 查找EXE文件（Windows）

      for (final file in archive) {
        final filePath = path.join(extractDir, file.name);

        if (file.isFile) {
          final outputFile = File(filePath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);

          // 根据文件扩展名分类查找
          final ext = path.extension(filePath).toLowerCase();
          if (ext == '.apk') {
            apkFilePath = filePath;
            _logger.log('找到APK文件: $filePath', tag: 'UPDATE');
          } else if (ext == '.dmg') {
            dmgFilePath = filePath;
            _logger.log('找到DMG文件: $filePath', tag: 'UPDATE');
          } else if (ext == '.exe' || ext == '.msi') {
            exeFilePath = filePath;
            _logger.log('找到EXE/MSI文件: $filePath', tag: 'UPDATE');
          }

          // 记录第一个文件路径（作为备选）
          if (extractedFilePath == null) {
            extractedFilePath = filePath;
          }
        } else {
          // 创建目录
          final dir = Directory(filePath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        }
      }

      // 根据平台优先返回对应的文件
      String? result;
      if (Platform.isAndroid) {
        result = apkFilePath ?? extractedFilePath;
      } else if (Platform.isMacOS) {
        // macOS: GitHub Actions打包的zip中包含dmg文件，优先查找dmg
        result = dmgFilePath ?? extractedFilePath;
      } else if (Platform.isWindows) {
        result = exeFilePath ?? extractedFilePath;
      } else {
        result = apkFilePath ?? dmgFilePath ?? exeFilePath ?? extractedFilePath;
      }

      _logger.log('zip文件解压完成: $extractDir, 返回文件: $result', tag: 'UPDATE');
      return result;
    } catch (e, stackTrace) {
      _logger.logError('解压zip文件失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 清理旧的更新包
  Future<void> _cleanupOldUpdatePackages(UpdateInfo oldUpdateInfo) async {
    try {
      _logger.log('开始清理旧的更新包: ${oldUpdateInfo.fileName}', tag: 'UPDATE');

      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();

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

  /// 获取下载目录（通过FileDownloadService的内部方法）
  Future<String> _getDownloadDirectory() async {
    // 使用反射或直接复制逻辑，这里我们直接复制逻辑
    if (Platform.isAndroid) {
      final directory = await getApplicationDocumentsDirectory();
      return path.join(directory.path, 'Downloads');
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      return path.join(directory.path, 'Downloads');
    } else if (Platform.isMacOS) {
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        return directory.path;
      }
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'Downloads');
    } else if (Platform.isWindows) {
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        return directory.path;
      }
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'Downloads');
    } else {
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'Downloads');
    }
  }

  /// 下载更新文件
  ///
  /// [updateInfo] 更新信息
  /// [onProgress] 进度回调 (received, total)
  ///
  /// 返回下载文件的路径（如果是zip则返回解压后的文件路径）
  Future<String?> downloadUpdateFile(
    UpdateInfo updateInfo, {
    Function(int received, int total)? onProgress,
  }) async {
    try {
      _logger.log('开始下载更新文件: ${updateInfo.fileName}', tag: 'UPDATE');

      final filePath = await _fileDownloadService.downloadFile(
        url: updateInfo.downloadUrl,
        fileName: updateInfo.fileName,
        onProgress: onProgress,
      );

      _logger.log('更新文件下载完成: $filePath', tag: 'UPDATE');

      // 如果有hash，进行校验
      if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
        final isValid = await verifyFileHash(filePath, updateInfo.fileHash!);
        if (!isValid) {
          // 删除下载的文件
          try {
            await File(filePath).delete();
          } catch (e) {
            // 忽略删除错误
          }
          throw Exception('文件hash校验失败，下载的文件可能已损坏或被篡改');
        }
      } else {
        _logger.log('更新信息中未包含hash，跳过校验', tag: 'UPDATE');
      }

      // 如果是zip文件，先解压
      if (updateInfo.fileType.toLowerCase() == 'zip') {
        _logger.log('检测到zip文件，开始解压', tag: 'UPDATE');
        final extractDir = path.join(path.dirname(filePath),
            'extracted_${path.basenameWithoutExtension(filePath)}');
        final extractedFilePath = await _extractZipFile(filePath, extractDir);

        if (extractedFilePath == null) {
          throw Exception('解压zip文件失败，未找到可执行文件');
        }

        _logger.log('zip文件解压完成: $extractedFilePath', tag: 'UPDATE');

        // 删除zip文件以节约空间
        try {
          await File(filePath).delete();
          _logger.log('已删除zip文件以节约空间: $filePath', tag: 'UPDATE');
        } catch (e) {
          _logger.log('删除zip文件失败: $e', tag: 'UPDATE');
        }

        // 返回解压后的文件路径
        return extractedFilePath;
      }

      return filePath;
    } catch (e, stackTrace) {
      _logger.logError('下载更新文件失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
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
