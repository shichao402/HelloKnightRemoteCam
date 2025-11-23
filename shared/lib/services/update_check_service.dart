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

  /// 检查更新（支持多个 URL，优先从 Gitee 获取，失败后从 GitHub 获取）
  ///
  /// [updateCheckUrls] 更新检查URL列表（按优先级排序，第一个优先）
  /// [currentVersionNumber] 当前版本号（格式: x.y.z，不含构建号）
  /// [getPlatform] 获取当前平台标识的回调（例如：'android', 'macos', 'windows'等）
  /// [target] 目标类型：'client' 或 'server'，用于从配置中提取对应的更新信息
  /// [avoidCache] 是否避免缓存（添加时间戳参数）
  ///
  /// 返回更新检查结果
  Future<UpdateCheckResult> checkForUpdate({
    required List<String> updateCheckUrls,
    required String currentVersionNumber,
    required String Function() getPlatform,
    String target = 'client',
    bool avoidCache = true,
  }) async {
    if (updateCheckUrls.isEmpty) {
      return UpdateCheckResult(
        hasUpdate: false,
        error: '更新检查URL未设置',
      );
    }

    // 使用提供的dio实例，如果没有则使用缓存的内部实例或创建新实例
    final dioInstance = dio ?? (_internalDio ??= Dio());

    // 尝试每个 URL，直到成功
    Exception? lastError;
    String? lastErrorUrl;

    for (int i = 0; i < updateCheckUrls.length; i++) {
      final updateCheckUrl = updateCheckUrls[i];
      if (updateCheckUrl.isEmpty) {
        continue;
      }

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

        final sourceName = i == 0 ? 'Gitee' : 'GitHub';
        onLog?.call('开始检查更新 ($sourceName)，URL: $url', tag: 'UPDATE');

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
          onLogError?.call('更新检查失败 ($sourceName)',
              error: 'HTTP ${response.statusCode}');
          lastError = Exception('HTTP ${response.statusCode}');
          lastErrorUrl = url;
          continue; // 尝试下一个 URL
        }

        // 处理响应数据：可能是 Map 或 String
        Map<String, dynamic> config;
        if (response.data is Map) {
          config = response.data as Map<String, dynamic>;
        } else if (response.data is String) {
          // 如果是字符串，需要手动解析 JSON
          config = jsonDecode(response.data as String) as Map<String, dynamic>;
        } else {
          onLogError?.call('更新检查失败 ($sourceName)',
              error: '响应数据格式不正确: ${response.data.runtimeType}');
          lastError = Exception('响应数据格式不正确');
          lastErrorUrl = url;
          continue; // 尝试下一个 URL
        }

        // 获取当前平台
        final platform = getPlatform();
        onLog?.call('当前平台: $platform', tag: 'UPDATE');

        // 从配置中获取目标更新信息（client 或 server）
        final targetConfig = config[target] as Map<String, dynamic>?;
        if (targetConfig == null) {
          onLog?.call('配置中未找到 $target 信息', tag: 'UPDATE');
          lastError = Exception('配置中未找到 $target 信息');
          lastErrorUrl = url;
          continue; // 尝试下一个 URL
        }

        // 获取平台特定的更新信息
        final platforms = targetConfig['platforms'] as Map<String, dynamic>?;
        if (platforms == null) {
          onLog?.call('配置中未找到平台信息', tag: 'UPDATE');
          lastError = Exception('配置中未找到平台信息');
          lastErrorUrl = url;
          continue; // 尝试下一个 URL
        }

        final platformConfig = platforms[platform] as Map<String, dynamic>?;
        if (platformConfig == null) {
          onLog?.call('配置中未找到平台 $platform 的信息', tag: 'UPDATE');
          lastError = Exception('配置中未找到平台 $platform 的信息');
          lastErrorUrl = url;
          continue; // 尝试下一个 URL
        }

        // 解析更新信息
        final updateInfo = UpdateInfo.fromJson(platformConfig);
        onLog?.call('最新版本: ${updateInfo.version} (来源: $sourceName)',
            tag: 'UPDATE');

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
        onLogError?.call('检查更新失败 ($sourceName)',
            error: e, stackTrace: stackTrace);
        lastError = e is Exception ? e : Exception(e.toString());
        lastErrorUrl = updateCheckUrl;
        // 继续尝试下一个 URL
      }
    }

    // 所有 URL 都失败了
    onLogError?.call('所有更新检查 URL 都失败', error: lastError);
    return UpdateCheckResult(
      hasUpdate: false,
      error: '检查更新失败: ${lastError?.toString() ?? "未知错误"}',
    );
  }

  /// 检查更新（单个 URL，向后兼容）
  ///
  /// [updateCheckUrl] 更新检查URL
  /// [currentVersionNumber] 当前版本号（格式: x.y.z，不含构建号）
  /// [getPlatform] 获取当前平台标识的回调（例如：'android', 'macos', 'windows'等）
  /// [target] 目标类型：'client' 或 'server'，用于从配置中提取对应的更新信息
  /// [avoidCache] 是否避免缓存（添加时间戳参数）
  ///
  /// 返回更新检查结果
  @Deprecated('使用 checkForUpdate 的 updateCheckUrls 参数替代')
  Future<UpdateCheckResult> checkForUpdateSingle({
    required String updateCheckUrl,
    required String currentVersionNumber,
    required String Function() getPlatform,
    String target = 'client',
    bool avoidCache = true,
  }) async {
    return checkForUpdate(
      updateCheckUrls: [updateCheckUrl],
      currentVersionNumber: currentVersionNumber,
      getPlatform: getPlatform,
      target: target,
      avoidCache: avoidCache,
    );
  }
}
