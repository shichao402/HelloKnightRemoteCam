import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'update_settings_service.dart';

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
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _logger.log('已打开下载链接', tag: 'UPDATE');
        return true;
      } else {
        _logger.logError('无法打开链接', error: 'URL: $url');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.logError('打开下载链接失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}

