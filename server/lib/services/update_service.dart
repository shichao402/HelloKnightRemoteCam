import 'dart:io';
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
        target: 'server',
        avoidCache: avoidCache,
      );

      // 如果发现新版本，保存更新信息到本地
      if (result.hasUpdate && result.updateInfo != null) {
        await _saveUpdateInfo(result.updateInfo);
      } else {
        // 清除保存的更新信息
        await _saveUpdateInfo(null);
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

      // 使用shared包的UpdateDownloadProcessor处理文件（hash校验、zip解压等）
      return await _downloadProcessor.processDownloadedFile(
        filePath,
        updateInfo,
        deleteZipAfterExtract: true,
      );
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

      // Android平台：如果是APK文件，需要先检查安装权限
      if (Platform.isAndroid) {
        final ext = path.extension(filePath).toLowerCase();
        if (ext == '.apk') {
          await requestInstallPermission();
          // 注意：即使权限未授予，也继续尝试打开文件
          // OpenFile插件会尝试打开，如果权限不足会返回错误
        }
      }
      
      final result = await OpenFile.open(filePath);
      
      if (result.type == ResultType.done) {
        _logger.log('已打开文件', tag: 'UPDATE');
        return true;
      } else if (result.type == ResultType.permissionDenied) {
        // 权限被拒绝，引导用户到设置页面
        _logger.log('打开文件权限被拒绝，引导用户到设置页面', tag: 'UPDATE');
        if (Platform.isAndroid) {
          try {
            // 打开应用设置页面，用户可以开启"允许从此来源安装应用"
            final opened = await openAppSettings();
            if (opened) {
              _logger.log('已打开应用设置页面', tag: 'UPDATE');
            } else {
              _logger.logError('无法打开应用设置页面');
            }
          } catch (e, stackTrace) {
            _logger.logError('打开应用设置页面失败', error: e, stackTrace: stackTrace);
          }
        }
        _logger.logError('打开文件失败', error: 'Result: ${result.type}, Message: ${result.message}');
        return false;
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

