import 'package:shared/shared.dart';
import 'logger_service.dart';
import 'version_file_provider.dart';
import 'version_parser.dart';
import 'version_fallback_service.dart';

/// 版本号服务
/// 从版本文件提供者读取版本号，失败时使用回退方案
/// 版本号由根目录的 VERSION.yaml 文件统一管理
class VersionService {
  static VersionService? _instance;

  /// 获取单例实例
  /// 如果提供了 [provider]，将使用它创建新实例（主要用于测试）
  factory VersionService({VersionFileProvider? provider}) {
    if (provider != null) {
      // 测试时允许注入自定义提供者
      return VersionService._internal(provider: provider);
    }
    _instance ??= VersionService._internal();
    return _instance!;
  }

  final ClientLoggerService _logger = ClientLoggerService();
  final VersionFileProvider _versionFileProvider;
  final VersionParser _versionParser = VersionParser();
  final VersionFallbackService _fallbackService = VersionFallbackService();

  VersionService._internal({VersionFileProvider? provider})
      : _versionFileProvider =
            provider ?? VersionFileProviderFactory.createDefault();

  VersionInfo? _cachedVersionInfo;
  bool _initialized = false;

  /// 初始化（从版本文件提供者读取版本号）
  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }

    // 尝试从版本文件提供者读取
    VersionInfo? versionInfo = await _tryLoadFromProvider();

    // 如果失败，尝试回退方案
    if (versionInfo == null) {
      versionInfo = await _tryLoadFromFallback();
    }

    // 如果还是失败，使用默认值
    _cachedVersionInfo = versionInfo ?? _fallbackService.getDefaultVersion();
    _initialized = true;
  }

  /// 尝试从版本文件提供者加载版本信息
  Future<VersionInfo?> _tryLoadFromProvider() async {
    try {
      final content = await _versionFileProvider.readVersionFile();
      final versionInfo = _versionParser.parseVersionFromYaml(content);
      final source = _versionFileProvider.getSourceDescription();
      _logger.log(
        '从版本文件读取版本号: ${versionInfo.fullVersion} (来源: $source)',
        tag: 'VERSION',
      );
      return versionInfo;
    } catch (e, stackTrace) {
      _logger.logError('从版本文件读取版本号失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 尝试从回退方案加载版本信息
  Future<VersionInfo?> _tryLoadFromFallback() async {
    try {
      final versionInfo = await _fallbackService.getVersionFromPackageInfo();
      _logger.log(
        '回退到 package_info_plus 读取版本号: ${versionInfo.fullVersion}',
        tag: 'VERSION',
      );
      return versionInfo;
    } catch (e, stackTrace) {
      _logger.logError('从 package_info_plus 读取版本号也失败',
          error: e, stackTrace: stackTrace);
      _logger.log('使用默认版本号: ${_fallbackService.getDefaultVersion()}',
          tag: 'VERSION');
      return null;
    }
  }

  /// 获取完整版本号（格式: x.y.z+build）
  Future<String> getVersion() async {
    if (_cachedVersionInfo != null) {
      return _cachedVersionInfo!.fullVersion;
    }

    await _initialize();
    return _cachedVersionInfo!.fullVersion;
  }

  /// 获取版本号部分（不含构建号，格式: x.y.z）
  Future<String> getVersionNumber() async {
    if (_cachedVersionInfo != null) {
      return _cachedVersionInfo!.versionNumber;
    }

    await _initialize();
    return _cachedVersionInfo!.versionNumber;
  }

  /// 获取构建号
  Future<String> getBuildNumber() async {
    if (_cachedVersionInfo != null) {
      return _cachedVersionInfo!.buildNumber;
    }

    await _initialize();
    return _cachedVersionInfo!.buildNumber;
  }

  /// 清除缓存（用于重新读取版本号）
  void clearCache() {
    _cachedVersionInfo = null;
    _initialized = false;
  }
}
