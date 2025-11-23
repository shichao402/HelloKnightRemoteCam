import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/update_info.dart';
import '../models/update_check_result.dart';
import '../utils/version_utils.dart';
import '../types/log_callbacks.dart';

/// 单个 URL 检查结果（内部使用）
class _CheckResult {
  final UpdateInfo? updateInfo;
  final bool hasUpdate;
  final Exception? error;
  final String sourceName;

  _CheckResult({
    this.updateInfo,
    this.hasUpdate = false,
    this.error,
    required this.sourceName,
  });
}

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

  /// 检查更新（支持多个 URL，并行下载所有配置，选择有更新的那个）
  ///
  /// [updateCheckUrls] 更新检查URL列表（并行请求所有 URL）
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

    // 获取当前平台
    final platform = getPlatform();
    onLog?.call('当前平台: $platform', tag: 'UPDATE');

    // 并行请求所有 URL
    final List<Future<_CheckResult>> futures = [];
    for (int i = 0; i < updateCheckUrls.length; i++) {
      final updateCheckUrl = updateCheckUrls[i];
      if (updateCheckUrl.isEmpty) {
        continue;
      }

      // 确定来源名称（根据 URL 内容判断，而不是索引）
      final sourceName = updateCheckUrl.contains('gitee.com') ? 'Gitee' : 'GitHub';

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

      onLog?.call('开始检查更新 ($sourceName)，URL: $url', tag: 'UPDATE');

      // 创建并行请求
      futures.add(_checkSingleUrl(
        dioInstance: dioInstance,
        url: url,
        sourceName: sourceName,
        platform: platform,
        target: target,
        currentVersionNumber: currentVersionNumber,
      ));
    }

    if (futures.isEmpty) {
      return UpdateCheckResult(
        hasUpdate: false,
        error: '没有有效的更新检查URL',
      );
    }

    // 使用 Future.any 等待第一个成功的结果（有更新的）
    // 哪个更快回来就用哪个
    onLog?.call('等待第一个成功的更新检查结果...', tag: 'UPDATE');
    
    _CheckResult? firstSuccessfulResult;
    Exception? lastError;
    final List<_CheckResult> allResults = [];
    
    // 等待第一个有更新的结果，或者所有请求完成
    try {
      // 创建一个 Completer 来跟踪第一个成功的结果
      final completer = Completer<_CheckResult?>();
      int completedCount = 0;
      
      for (final future in futures) {
        future.then((result) {
          completedCount++;
          allResults.add(result);
          
          // 如果这是第一个有更新的结果，且还没有设置过，就使用它
          if (result.error == null && 
              result.updateInfo != null && 
              result.hasUpdate && 
              !completer.isCompleted) {
            onLog?.call('${result.sourceName} 最先返回，发现新版本: ${result.updateInfo!.version}', tag: 'UPDATE');
            completer.complete(result);
          }
          
          // 如果所有请求都完成了，但还没有成功的结果，完成 completer
          if (completedCount == futures.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }).catchError((error) {
          completedCount++;
          // 如果所有请求都失败了，完成 completer
          if (completedCount == futures.length && !completer.isCompleted) {
            completer.complete(null);
          }
        });
      }
      
      firstSuccessfulResult = await completer.future;
    } catch (e) {
      onLogError?.call('等待更新检查结果时出错', error: e);
    }

    // 如果第一个成功的结果有更新，直接使用它
    if (firstSuccessfulResult != null) {
      final updateInfo = firstSuccessfulResult.updateInfo!;
      onLog?.call(
          '使用最先返回的结果: ${updateInfo.version} (来源: ${firstSuccessfulResult.sourceName})',
          tag: 'UPDATE');
      onLog?.call(
          '更新信息详情 (来源: ${firstSuccessfulResult.sourceName}):', tag: 'UPDATE');
      onLog?.call('  版本号: ${updateInfo.version}', tag: 'UPDATE');
      onLog?.call('  版本号(不含构建号): ${updateInfo.versionNumber}', tag: 'UPDATE');
      onLog?.call('  下载 URL: ${updateInfo.downloadUrl}', tag: 'UPDATE');
      onLog?.call('  文件名: ${updateInfo.fileName}', tag: 'UPDATE');
      onLog?.call('  文件类型: ${updateInfo.fileType}', tag: 'UPDATE');
      onLog?.call('  平台: ${updateInfo.platform}', tag: 'UPDATE');
      if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
        onLog?.call('  文件 Hash: ${updateInfo.fileHash}', tag: 'UPDATE');
      } else {
        onLog?.call('  文件 Hash: 未提供', tag: 'UPDATE');
      }
      if (updateInfo.releaseNotes != null && updateInfo.releaseNotes!.isNotEmpty) {
        onLog?.call('  更新说明: ${updateInfo.releaseNotes}', tag: 'UPDATE');
      }
      return UpdateCheckResult(
        hasUpdate: true,
        updateInfo: updateInfo,
      );
    }

    // 如果没有成功的结果，等待所有请求完成，检查是否有无更新的结果
    onLog?.call('等待所有更新检查完成...', tag: 'UPDATE');
    final results = await Future.wait(futures);
    
    // 收集所有结果
    final List<_CheckResult> noUpdateResults = [];
    for (final result in results) {
      if (result.error != null) {
        onLogError?.call('${result.sourceName} 检查失败', error: result.error);
        lastError = result.error;
      } else if (result.updateInfo != null) {
        if (result.hasUpdate) {
          // 这种情况不应该发生，因为应该已经被 firstSuccessfulResult 处理了
          onLog?.call('  ${result.sourceName}: 发现新版本 ${result.updateInfo!.version}', tag: 'UPDATE');
        } else {
          onLog?.call('  ${result.sourceName}: 版本 ${result.updateInfo!.version} 不高于当前版本', tag: 'UPDATE');
          noUpdateResults.add(result);
        }
      }
    }

    if (noUpdateResults.isNotEmpty) {
      onLog?.call('所有更新源检查完成，当前已是最新版本', tag: 'UPDATE');
      return UpdateCheckResult(
        hasUpdate: false,
      );
    }

    // 所有检查都失败
    onLogError?.call('所有更新检查 URL 都失败', error: lastError);
    return UpdateCheckResult(
      hasUpdate: false,
      error: '检查更新失败: ${lastError?.toString() ?? "未知错误"}',
    );
  }

  /// 检查单个 URL（内部方法，用于并行请求）
  Future<_CheckResult> _checkSingleUrl({
    required Dio dioInstance,
    required String url,
    required String sourceName,
    required String platform,
    required String target,
    required String currentVersionNumber,
  }) async {
    try {
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
        return _CheckResult(
          error: Exception('HTTP ${response.statusCode}'),
          sourceName: sourceName,
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
        onLogError?.call('更新检查失败 ($sourceName)',
            error: '响应数据格式不正确: ${response.data.runtimeType}');
        return _CheckResult(
          error: Exception('响应数据格式不正确'),
          sourceName: sourceName,
        );
      }

      // 从配置中获取目标更新信息（client 或 server）
      final targetConfig = config[target] as Map<String, dynamic>?;
      if (targetConfig == null) {
        onLog?.call('配置中未找到 $target 信息 ($sourceName)', tag: 'UPDATE');
        return _CheckResult(
          error: Exception('配置中未找到 $target 信息'),
          sourceName: sourceName,
        );
      }

      // 获取平台特定的更新信息
      final platforms = targetConfig['platforms'] as Map<String, dynamic>?;
      if (platforms == null) {
        onLog?.call('配置中未找到平台信息 ($sourceName)', tag: 'UPDATE');
        return _CheckResult(
          error: Exception('配置中未找到平台信息'),
          sourceName: sourceName,
        );
      }

      final platformConfig = platforms[platform] as Map<String, dynamic>?;
      if (platformConfig == null) {
        onLog?.call('配置中未找到平台 $platform 的信息 ($sourceName)', tag: 'UPDATE');
        return _CheckResult(
          error: Exception('配置中未找到平台 $platform 的信息'),
          sourceName: sourceName,
        );
      }

      // 解析更新信息
      final updateInfo = UpdateInfo.fromJson(platformConfig);
      onLog?.call('最新版本: ${updateInfo.version} (来源: $sourceName)',
          tag: 'UPDATE');
      onLog?.call('从 $sourceName 获取的更新信息:', tag: 'UPDATE');
      onLog?.call('  版本号: ${updateInfo.version}', tag: 'UPDATE');
      onLog?.call('  版本号(不含构建号): ${updateInfo.versionNumber}', tag: 'UPDATE');
      onLog?.call('  下载 URL: ${updateInfo.downloadUrl}', tag: 'UPDATE');
      onLog?.call('  文件名: ${updateInfo.fileName}', tag: 'UPDATE');
      onLog?.call('  文件类型: ${updateInfo.fileType}', tag: 'UPDATE');
      onLog?.call('  平台: ${updateInfo.platform}', tag: 'UPDATE');
      if (updateInfo.fileHash != null && updateInfo.fileHash!.isNotEmpty) {
        onLog?.call('  文件 Hash: ${updateInfo.fileHash}', tag: 'UPDATE');
      } else {
        onLog?.call('  文件 Hash: 未提供', tag: 'UPDATE');
      }

      // 比较版本（使用工具类）
      final hasUpdate = VersionUtils.compareVersions(
          updateInfo.versionNumber, currentVersionNumber);

      return _CheckResult(
        updateInfo: updateInfo,
        hasUpdate: hasUpdate,
        sourceName: sourceName,
      );
    } catch (e, stackTrace) {
      onLogError?.call('检查更新失败 ($sourceName)',
          error: e, stackTrace: stackTrace);
      return _CheckResult(
        error: e is Exception ? e : Exception(e.toString()),
        sourceName: sourceName,
      );
    }
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
