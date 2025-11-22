import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:shared/shared.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'update_settings_service.dart';
import 'file_download_service.dart';

/// 更新服务（服务端）
/// 负责检查更新、下载更新文件
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  final LoggerService _logger = LoggerService();
  final VersionService _versionService = VersionService();
  final UpdateSettingsService _updateSettings = UpdateSettingsService();
  final Dio _dio = Dio();
  final FileDownloadService _fileDownloadService = FileDownloadService();
  
  // 使用shared包的服务，注入logger回调
  late final ArchiveService _archiveService = ArchiveService(
    onLog: (message, {tag}) => _logger.log(message, tag: tag ?? 'ARCHIVE'),
    onLogError: (message, {error, stackTrace}) => _logger.logError(message, error: error, stackTrace: stackTrace),
  );

  // 默认更新检查URL（可以从设置中配置）
  String _updateCheckUrl = '';

  /// 设置更新检查URL
  void setUpdateCheckUrl(String url) {
    _updateCheckUrl = url;
    _logger.log('设置更新检查URL: $url', tag: 'UPDATE');
  }

  /// 获取当前平台标识
  String _getCurrentPlatform() {
    if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else {
      return 'unknown';
    }
  }

  /// 比较版本号（使用shared包的VersionUtils）
  bool _compareVersions(String version1, String version2) {
    return VersionUtils.compareVersions(version1, version2);
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
        _logger.logError('更新检查失败', error: '响应数据格式不正确: ${response.data.runtimeType}');
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

      // 从配置中获取服务器更新信息
      final serverConfig = config['server'] as Map<String, dynamic>?;
      if (serverConfig == null) {
        _logger.log('配置中未找到服务器信息', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '配置中未找到服务器信息',
        );
      }

      // 获取平台特定的更新信息
      final platforms = serverConfig['platforms'] as Map<String, dynamic>?;
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
        // 保存更新信息到本地
        await _saveUpdateInfo(updateInfo);
        return UpdateCheckResult(
          hasUpdate: true,
          updateInfo: updateInfo,
        );
      } else {
        _logger.log('当前已是最新版本', tag: 'UPDATE');
        // 清除保存的更新信息
        await _saveUpdateInfo(null);
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

  /// 保存更新信息到本地
  Future<void> _saveUpdateInfo(UpdateInfo? updateInfo) async {
    await _updateSettings.saveUpdateInfo(updateInfo);
  }
  
  /// 获取保存的更新信息
  Future<UpdateInfo?> getSavedUpdateInfo() async {
    return await _updateSettings.getUpdateInfo();
  }
  
  /// 检查是否有可用的更新
  Future<bool> hasUpdate() async {
    return await _updateSettings.hasUpdate();
  }
  
  /// 打开下载链接（在浏览器中打开）
  Future<bool> openDownloadUrl(String url) async {
    try {
      _logger.log('打开下载链接: $url', tag: 'UPDATE');
      final uri = Uri.parse(url);
      
      // 检查URL是否有效
      if (!uri.hasScheme || (!uri.scheme.startsWith('http') && !uri.scheme.startsWith('https'))) {
        _logger.logError('无效的URL格式', error: 'URL: $url');
        return false;
      }
      
      // 尝试检查是否可以启动URL
      bool canLaunch = false;
      try {
        canLaunch = await canLaunchUrl(uri);
      } catch (e) {
        _logger.log('canLaunchUrl检查失败，尝试直接打开: $e', tag: 'UPDATE');
        // 即使检查失败，也尝试直接打开
        canLaunch = true;
      }
      
      if (canLaunch) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _logger.log('已打开下载链接', tag: 'UPDATE');
          return true;
        } catch (e, stackTrace) {
          _logger.logError('launchUrl调用失败', error: e, stackTrace: stackTrace);
          // 尝试使用platform模式
          try {
            await launchUrl(uri, mode: LaunchMode.platformDefault);
            _logger.log('已使用platform模式打开下载链接', tag: 'UPDATE');
            return true;
          } catch (e2, stackTrace2) {
            _logger.logError('platform模式打开链接也失败', error: e2, stackTrace: stackTrace2);
            return false;
          }
        }
      } else {
        _logger.logError('无法打开链接', error: 'URL: $url, canLaunchUrl返回false');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.logError('打开下载链接失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }
  
  /// 请求存储权限（Android需要）
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) {
      return true; // 非Android平台不需要权限
    }
    
    try {
      _logger.log('请求存储权限', tag: 'UPDATE');
      
      // Android 13+ (API 33+) 使用新的权限模型
      if (await Permission.photos.isGranted || 
          await Permission.videos.isGranted ||
          await Permission.audio.isGranted) {
        _logger.log('媒体权限已授予', tag: 'UPDATE');
        return true;
      }
      
      // Android 10-12 (API 29-32) 需要存储权限
      if (await Permission.storage.isGranted) {
        _logger.log('存储权限已授予', tag: 'UPDATE');
        return true;
      }
      
      // 请求权限
      final status = await Permission.storage.request();
      if (status.isGranted) {
        _logger.log('存储权限已授予', tag: 'UPDATE');
        return true;
      } else {
        _logger.logError('存储权限被拒绝', error: 'Status: $status');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.logError('请求存储权限失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 请求安装APK权限（Android 8.0+需要）
  /// 注意：此权限需要通过系统设置页面手动开启，无法通过代码直接请求
  Future<bool> requestInstallPermission() async {
    if (!Platform.isAndroid) {
      return true; // 非Android平台不需要权限
    }
    
    try {
      _logger.log('检查安装APK权限', tag: 'UPDATE');
      
      // 尝试检查权限状态（如果permission_handler支持）
      try {
        final status = await Permission.requestInstallPackages.status;
        if (status.isGranted) {
          _logger.log('安装APK权限已授予', tag: 'UPDATE');
          return true;
        }
        _logger.log('安装APK权限未授予，将尝试打开文件（系统会引导用户到设置页面）', tag: 'UPDATE');
      } catch (e) {
        // permission_handler可能不支持此权限，这是正常的
        _logger.log('无法检查安装APK权限（可能不支持），将直接尝试打开文件', tag: 'UPDATE');
      }
      
      // 即使权限检查失败，也返回true，让open_file插件处理
      // open_file插件会引导用户到设置页面开启"允许从此来源安装应用"
      return true;
    } catch (e, stackTrace) {
      _logger.logError('检查安装APK权限失败', error: e, stackTrace: stackTrace);
      // 即使出错也返回true，让open_file插件尝试打开
      return true;
    }
  }
  
  /// 解压zip文件（使用shared包的ArchiveService）
  Future<String?> _extractZipFile(String zipPath, String extractDir) async {
    return await _archiveService.extractZipFile(zipPath, extractDir);
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
      
      // Android需要请求存储权限
      if (Platform.isAndroid) {
        final hasPermission = await requestStoragePermission();
        if (!hasPermission) {
          throw Exception('存储权限被拒绝，无法下载文件');
        }
      }
      
      final filePath = await _fileDownloadService.downloadFile(
        url: updateInfo.downloadUrl,
        fileName: updateInfo.fileName,
        onProgress: onProgress,
      );
      
      _logger.log('更新文件下载完成: $filePath', tag: 'UPDATE');

      // 如果是zip文件，先解压
      if (updateInfo.fileType.toLowerCase() == 'zip') {
        _logger.log('检测到zip文件，开始解压', tag: 'UPDATE');
        final extractDir = path.join(path.dirname(filePath),
            'extracted_${path.basenameWithoutExtension(filePath)}');
        final extractedFilePath = await _extractZipFile(filePath, extractDir);

        if (extractedFilePath == null) {
          // 如果找不到预期的安装文件，返回zip文件路径让系统打开zip文件
          _logger.log('未找到预期的安装文件，将打开zip文件本身: $filePath', tag: 'UPDATE');
          return filePath;
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
  Future<bool> openDownloadedFile(String filePath) async {
    try {
      _logger.log('打开下载的文件: $filePath', tag: 'UPDATE');
      
      final file = File(filePath);
      if (!await file.exists()) {
        _logger.logError('文件不存在', error: 'Path: $filePath');
        return false;
      }

      // Android平台：如果是APK文件，需要先请求安装权限
      if (Platform.isAndroid) {
        final ext = path.extension(filePath).toLowerCase();
        if (ext == '.apk') {
          final hasPermission = await requestInstallPermission();
          if (!hasPermission) {
            _logger.logError('安装APK权限被拒绝，无法打开APK文件', error: 'Path: $filePath');
            return false;
          }
        }
      }
      
      final result = await OpenFile.open(filePath);
      
      if (result.type == ResultType.done) {
        _logger.log('已打开文件', tag: 'UPDATE');
        return true;
      } else {
        _logger.logError('打开文件失败', error: 'Result: ${result.type}, Message: ${result.message}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.logError('打开文件失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}

