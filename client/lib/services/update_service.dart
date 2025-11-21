import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'logger_service.dart';
import 'version_service.dart';

/// 更新信息模型
class UpdateInfo {
  final String version;
  final String versionNumber;
  final String downloadUrl;
  final String fileName;
  final String fileType;
  final String platform;
  final String? releaseNotes;

  UpdateInfo({
    required this.version,
    required this.versionNumber,
    required this.downloadUrl,
    required this.fileName,
    required this.fileType,
    required this.platform,
    this.releaseNotes,
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

  // 默认更新检查URL（可以从设置中配置）
  String _updateCheckUrl = '';

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
  Future<UpdateCheckResult> checkForUpdate() async {
    if (_updateCheckUrl.isEmpty) {
      return UpdateCheckResult(
        hasUpdate: false,
        error: '更新检查URL未设置',
      );
    }

    try {
      _logger.log('开始检查更新，URL: $_updateCheckUrl', tag: 'UPDATE');

      // 获取更新配置
      final response = await _dio.get(
        _updateCheckUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'Accept': 'application/json',
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

      final config = response.data as Map<String, dynamic>;
      
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
      final hasUpdate = _compareVersions(updateInfo.versionNumber, currentVersionNumber);
      
      if (hasUpdate) {
        _logger.log('发现新版本: ${updateInfo.version}', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: true,
          updateInfo: updateInfo,
        );
      } else {
        _logger.log('当前已是最新版本', tag: 'UPDATE');
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

  /// 下载更新文件
  /// 返回下载文件的路径
  Future<String?> downloadUpdate(UpdateInfo updateInfo, Function(int, int)? onProgress) async {
    try {
      _logger.log('开始下载更新: ${updateInfo.fileName}', tag: 'UPDATE');

      // 获取下载目录
      final directory = await _getDownloadDirectory();
      final filePath = '${directory.path}/${updateInfo.fileName}';

      // 下载文件
      await _dio.download(
        updateInfo.downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (onProgress != null && total > 0) {
            onProgress(received, total);
          }
        },
        options: Options(
          headers: {
            'Accept': '*/*',
          },
        ),
      );

      _logger.log('下载完成: $filePath', tag: 'UPDATE');
      return filePath;
    } catch (e, stackTrace) {
      _logger.logError('下载更新失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 获取下载目录
  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // 桌面平台使用应用支持目录
      final appSupportDir = await getApplicationSupportDirectory();
      final downloadDir = Directory('${appSupportDir.path}/downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    } else {
      // Android/iOS 使用应用文档目录
      final documentsDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${documentsDir.path}/downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    }
  }

  /// 安装更新（打开下载的文件）
  Future<bool> installUpdate(String filePath) async {
    try {
      _logger.log('准备安装更新: $filePath', tag: 'UPDATE');

      final file = File(filePath);
      if (!await file.exists()) {
        _logger.logError('更新文件不存在', error: '文件路径: $filePath');
        return false;
      }

      // 使用 open_file 包打开文件（让系统处理安装）
      if (Platform.isMacOS) {
        // macOS: 解压zip文件并打开
        if (filePath.endsWith('.zip')) {
          // 解压zip文件
          final zipDir = Directory('${file.parent.path}/extracted');
          if (await zipDir.exists()) {
            await zipDir.delete(recursive: true);
          }
          await zipDir.create(recursive: true);
          
          // 使用系统命令解压
          final result = await Process.run('unzip', [
            '-q',
            filePath,
            '-d',
            zipDir.path,
          ]);
          
          if (result.exitCode == 0) {
            // 查找.app文件
            final appFiles = zipDir.listSync(recursive: true)
                .where((e) => e.path.endsWith('.app'))
                .toList();
            
            if (appFiles.isNotEmpty) {
              // 打开Finder显示解压后的文件
              await Process.run('open', [zipDir.path]);
              _logger.log('已打开Finder显示解压后的应用', tag: 'UPDATE');
              return true;
            }
          }
        }
      } else if (Platform.isWindows) {
        // Windows: 解压zip文件并打开文件夹
        if (filePath.endsWith('.zip')) {
          final zipDir = Directory('${file.parent.path}/extracted');
          if (await zipDir.exists()) {
            await zipDir.delete(recursive: true);
          }
          await zipDir.create(recursive: true);
          
          // 使用PowerShell解压
          final result = await Process.run('powershell', [
            '-Command',
            'Expand-Archive',
            '-Path',
            filePath,
            '-DestinationPath',
            zipDir.path,
            '-Force',
          ]);
          
          if (result.exitCode == 0) {
            // 打开文件夹
            await Process.run('explorer', [zipDir.path]);
            _logger.log('已打开文件夹显示解压后的文件', tag: 'UPDATE');
            return true;
          }
        }
      } else if (Platform.isAndroid) {
        // Android: 使用open_file打开APK文件
        if (filePath.endsWith('.apk')) {
          await OpenFile.open(filePath);
          _logger.log('已打开APK安装器: $filePath', tag: 'UPDATE');
          return true;
        }
      }

      // 默认：使用open_file打开文件
      await OpenFile.open(filePath);
      _logger.log('已打开更新文件: $filePath', tag: 'UPDATE');
      return true;
    } catch (e, stackTrace) {
      _logger.logError('安装更新失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}

