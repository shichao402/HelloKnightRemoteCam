import 'package:yaml/yaml.dart';
import '../models/version_info.dart';
import '../types/log_callbacks.dart';

/// 版本文件解析服务
/// 负责解析 YAML 格式的版本文件
/// 客户端和服务端共享
class VersionParserService {
  /// 日志回调（可选）
  LogCallback? onLog;
  LogErrorCallback? onLogError;

  VersionParserService({this.onLog, this.onLogError});

  /// 从 YAML 内容解析版本信息
  /// [yamlContent] YAML 文件内容
  /// [target] 目标类型：'client' 或 'server'
  /// 抛出 FormatException 如果解析失败
  VersionInfo parseVersionFromYaml(String yamlContent,
      {String target = 'client'}) {
    try {
      final yamlDoc = loadYaml(yamlContent);

      if (yamlDoc is! Map) {
        throw FormatException('版本文件格式不正确，应为 YAML Map');
      }

      final targetMap = yamlDoc[target] as Map?;
      if (targetMap == null) {
        throw FormatException('版本文件中未找到 $target 字段');
      }

      final version = targetMap['version'] as String?;
      if (version == null || version.isEmpty) {
        throw FormatException('版本文件中未找到 $target.version 字段');
      }

      return VersionInfo.fromString(version);
    } catch (e) {
      if (e is FormatException) {
        rethrow;
      }
      throw FormatException('解析版本文件失败: $e', e);
    }
  }

  /// 从 YAML 内容解析客户端版本信息
  VersionInfo parseClientVersionFromYaml(String yamlContent) {
    return parseVersionFromYaml(yamlContent, target: 'client');
  }

  /// 从 YAML 内容解析服务器版本信息
  VersionInfo parseServerVersionFromYaml(String yamlContent) {
    return parseVersionFromYaml(yamlContent, target: 'server');
  }
}
