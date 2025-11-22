import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared/shared.dart';
import 'logger_service.dart';

/// 版本回退服务
/// 当主要版本源失败时，提供回退方案
class VersionFallbackService {
  final ClientLoggerService _logger = ClientLoggerService();

  /// 从 package_info_plus 获取版本号（回退方案）
  Future<VersionInfo> getVersionFromPackageInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return VersionInfo.fromString(
          '${packageInfo.version}+${packageInfo.buildNumber}');
    } catch (e, stackTrace) {
      _logger.logError('从 package_info_plus 读取版本号失败',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 获取默认版本号
  VersionInfo getDefaultVersion() {
    return VersionInfo.fromString('1.0.0+1');
  }
}
