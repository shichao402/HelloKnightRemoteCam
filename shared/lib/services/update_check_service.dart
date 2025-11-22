import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/update_info.dart';
import '../models/update_check_result.dart';
import '../utils/version_utils.dart';
import '../types/log_callbacks.dart';

/// 更新检查服务
/// 负责从远程服务器检查更新、解析更新配置、比较版本
/// 客户端和服务端共享
class UpdateCheckService {
  /// 日志回调（可选）
  LogCallback? onLog;
  LogErrorCallback? onLogError;

  /// Dio实例（可选，如果不提供则创建新实例）
  final Dio? dio;

  /// 内部Dio实例（当dio为null时使用）
  Dio? _internalDio;

  UpdateCheckService({
    this.onLog,
    this.onLogError,
    this.dio,
  });

  /// 检查更新
  /// 
  /// [updateCheckUrl] 更新检查URL
  /// [currentVersionNumber] 当前版本号（格式: x.y.z，不含构建号）
  /// [getPlatform] 获取当前平台标识的回调（例如：'android', 'macos', 'windows'等）
  /// [target] 目标类型：'client' 或 'server'，用于从配置中提取对应的更新信息
  /// [avoidCache] 是否避免缓存（添加时间戳参数）
  /// 
  /// 返回更新检查结果
  Future<UpdateCheckResult> checkForUpdate({
    required String updateCheckUrl,
    required String currentVersionNumber,
    required String Function() getPlatform,
    String target = 'client',
    bool avoidCache = true,
  }) async {
    if (updateCheckUrl.isEmpty) {
      return UpdateCheckResult(
        hasUpdate: false,
        error: '更新检查URL未设置',
      );
    }

    // 使用提供的dio实例，如果没有则使用缓存的内部实例或创建新实例
    final dioInstance = dio ?? (_internalDio ??= Dio());

    try {
      // 添加时间戳参数避免缓存
      String url = updateCheckUrl;
      if (avoidCache) {
        final uri = Uri.parse(url);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        url = uri.replace(queryParameters: {
          ...uri.queryParameters,
          '_t': timestamp.toString(),
        }).toString();
      }

      onLog?.call('开始检查更新，URL: $url', tag: 'UPDATE');

      // 获取更新配置
      final response = await dioInstance.get(
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
        onLogError?.call('更新检查失败', error: 'HTTP ${response.statusCode}');
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
        onLogError?.call('更新检查失败',
            error: '响应数据格式不正确: ${response.data.runtimeType}');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '响应数据格式不正确',
        );
      }

      // 获取当前平台
      final platform = getPlatform();
      onLog?.call('当前平台: $platform', tag: 'UPDATE');

      // 从配置中获取目标更新信息（client 或 server）
      final targetConfig = config[target] as Map<String, dynamic>?;
      if (targetConfig == null) {
        onLog?.call('配置中未找到 $target 信息', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '配置中未找到 $target 信息',
        );
      }

      // 获取平台特定的更新信息
      final platforms = targetConfig['platforms'] as Map<String, dynamic>?;
      if (platforms == null) {
        onLog?.call('配置中未找到平台信息', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '配置中未找到平台信息',
        );
      }

      final platformConfig = platforms[platform] as Map<String, dynamic>?;
      if (platformConfig == null) {
        onLog?.call('配置中未找到平台 $platform 的信息', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
          error: '配置中未找到平台 $platform 的信息',
        );
      }

      // 解析更新信息
      final updateInfo = UpdateInfo.fromJson(platformConfig);
      onLog?.call('最新版本: ${updateInfo.version}', tag: 'UPDATE');

      // 比较版本（使用工具类）
      final hasUpdate = VersionUtils.compareVersions(
          updateInfo.versionNumber, currentVersionNumber);

      if (hasUpdate) {
        onLog?.call('发现新版本: ${updateInfo.version}', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: true,
          updateInfo: updateInfo,
        );
      } else {
        onLog?.call('当前已是最新版本', tag: 'UPDATE');
        return UpdateCheckResult(
          hasUpdate: false,
        );
      }
    } catch (e, stackTrace) {
      onLogError?.call('检查更新失败', error: e, stackTrace: stackTrace);
      return UpdateCheckResult(
        hasUpdate: false,
        error: '检查更新失败: $e',
      );
    }
  }
}

