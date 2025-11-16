import 'package:package_info_plus/package_info_plus.dart';
import 'logger_service.dart';

/// 版本号服务
/// 从 pubspec.yaml 读取版本号（通过 package_info_plus），不依赖外部平台
/// 版本号由根目录的 VERSION 文件统一管理，通过部署脚本同步到 pubspec.yaml
class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  final LoggerService _logger = LoggerService();
  
  String? _cachedVersion;
  String? _cachedVersionNumber;
  String? _cachedBuildNumber;

  /// 获取完整版本号（格式: x.y.z+build）
  Future<String> getVersion() async {
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      _logger.log('读取版本号: $_cachedVersion', tag: 'VERSION');
      return _cachedVersion!;
    } catch (e, stackTrace) {
      _logger.logError('读取版本号失败', error: e, stackTrace: stackTrace);
      _cachedVersion = '1.0.0+1';
      return _cachedVersion!;
    }
  }

  /// 获取版本号部分（不含构建号，格式: x.y.z）
  Future<String> getVersionNumber() async {
    if (_cachedVersionNumber != null) {
      return _cachedVersionNumber!;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedVersionNumber = packageInfo.version;
      return _cachedVersionNumber!;
    } catch (e, stackTrace) {
      _logger.logError('读取版本号失败', error: e, stackTrace: stackTrace);
      _cachedVersionNumber = '1.0.0';
      return _cachedVersionNumber!;
    }
  }

  /// 获取构建号
  Future<String> getBuildNumber() async {
    if (_cachedBuildNumber != null) {
      return _cachedBuildNumber!;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedBuildNumber = packageInfo.buildNumber;
      return _cachedBuildNumber!;
    } catch (e, stackTrace) {
      _logger.logError('读取构建号失败', error: e, stackTrace: stackTrace);
      _cachedBuildNumber = '1';
      return _cachedBuildNumber!;
    }
  }

  /// 清除缓存（用于重新读取版本号）
  void clearCache() {
    _cachedVersion = null;
    _cachedVersionNumber = null;
    _cachedBuildNumber = null;
  }
}
