import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';
import 'package:shared/shared.dart';
import 'logger_service.dart';
import 'version_service.dart';

/// 版本兼容性检查服务
/// 检查服务器版本是否符合客户端要求
class VersionCompatibilityService {
  static final VersionCompatibilityService _instance =
      VersionCompatibilityService._internal();
  factory VersionCompatibilityService() => _instance;
  VersionCompatibilityService._internal();

  final ClientLoggerService _logger = ClientLoggerService();
  final VersionService _versionService = VersionService();

  String? _minServerVersion;
  String? _clientVersion;

  /// 初始化（读取最小服务器版本要求）
  Future<void> initialize() async {
    try {
      _minServerVersion = await _readMinServerVersion();
      _clientVersion = await _versionService.getVersionNumber();
      _logger.log('版本兼容性服务已初始化', tag: 'VERSION_COMPAT');
      _logger.log('客户端版本: $_clientVersion, 最小服务器版本: $_minServerVersion',
          tag: 'VERSION_COMPAT');
    } catch (e, stackTrace) {
      _logger.logError('初始化版本兼容性服务失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 检查服务器版本是否兼容
  /// 返回 (isCompatible, reason)
  Future<(bool, String?)> checkServerVersion(String serverVersion) async {
    try {
      if (_minServerVersion == null) {
        await initialize();
      }

      if (_minServerVersion == null) {
        _logger.log('无法读取最小服务器版本要求，允许连接', tag: 'VERSION_COMPAT');
        return (true, null);
      }

      // 提取版本号部分（去掉构建号）
      final serverVersionNumber = serverVersion.split('+').first;

      _logger.log(
          '检查服务器版本兼容性: 服务器=$serverVersionNumber, 要求最小版本=$_minServerVersion',
          tag: 'VERSION_COMPAT');

      final isCompatible =
          _compareVersions(serverVersionNumber, _minServerVersion!);

      if (!isCompatible) {
        final reason =
            '服务器版本 $serverVersionNumber 低于客户端要求的最小版本 $_minServerVersion';
        _logger.log('版本不兼容: $reason', tag: 'VERSION_COMPAT');
        return (false, reason);
      }

      _logger.log('服务器版本兼容', tag: 'VERSION_COMPAT');
      return (true, null);
    } catch (e, stackTrace) {
      _logger.logError('检查服务器版本失败', error: e, stackTrace: stackTrace);
      // 出错时允许连接（避免因版本检查问题导致无法连接）
      return (true, null);
    }
  }

  /// 比较版本号
  /// 返回 true 如果 version1 >= version2
  bool _compareVersions(String version1, String version2) {
    // 使用 shared 包的版本比较工具
    return VersionUtils.compareVersionsGreaterOrEqual(version1, version2);
  }

  /// 获取客户端版本号
  Future<String> getClientVersion() async {
    _clientVersion ??= await _versionService.getVersionNumber();
    return _clientVersion!;
  }

  /// 获取最小服务器版本要求
  Future<String> getMinServerVersion() async {
    if (_minServerVersion == null) {
      await initialize();
    }
    return _minServerVersion ?? '1.0.0';
  }

  /// 从assets/VERSION.yaml文件读取最小服务器版本要求
  /// 优先从打包的assets文件读取，如果失败则尝试从文件系统查找（开发环境）
  Future<String?> _readMinServerVersion() async {
    try {
      // 优先从打包的assets/VERSION.yaml文件读取
      try {
        final content = await rootBundle.loadString('assets/VERSION.yaml');
        final yamlDoc = loadYaml(content);
        if (yamlDoc is Map) {
          final compatibility = yamlDoc['compatibility'];
          if (compatibility is Map) {
            final minVersion = compatibility['min_server_version'];
            if (minVersion != null && minVersion.toString().isNotEmpty) {
              final version = minVersion.toString();
              _logger.log('从assets/VERSION.yaml文件读取最小服务器版本: $version',
                  tag: 'VERSION_COMPAT');
              return version;
            }
          }
        }
      } catch (e) {
        _logger.log('从assets读取VERSION.yaml失败，尝试从文件系统查找: $e',
            tag: 'VERSION_COMPAT');
      }

      // 开发环境：尝试从应用文档目录向上查找项目根目录的VERSION.yaml文件
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        Directory? currentDir = Directory(appDocDir.path);

        // 最多向上查找10层目录
        for (int i = 0; i < 10; i++) {
          if (currentDir == null) break;

          // 优先查找 VERSION.yaml
          var versionFile = File(path.join(currentDir.path, 'VERSION.yaml'));
          var found = false;

          if (await versionFile.exists()) {
            found = true;
          } else {
            // 兼容旧格式 VERSION
            versionFile = File(path.join(currentDir.path, 'VERSION'));
            if (await versionFile.exists()) {
              found = true;
            }
          }

          if (found) {
            final content = await versionFile.readAsString();

            // 尝试解析YAML格式
            try {
              final yamlDoc = loadYaml(content);
              if (yamlDoc is Map) {
                final compatibility = yamlDoc['compatibility'];
                if (compatibility is Map) {
                  final minVersion = compatibility['min_server_version'];
                  if (minVersion != null && minVersion.toString().isNotEmpty) {
                    final version = minVersion.toString();
                    _logger.log('从文件系统VERSION.yaml文件读取最小服务器版本: $version',
                        tag: 'VERSION_COMPAT');
                    return version;
                  }
                }
              }
            } catch (e) {
              // YAML解析失败，尝试旧格式
            }

            // 旧格式解析
            final lines = content.split('\n');
            for (final line in lines) {
              if (line.trim().startsWith('MIN_SERVER_VERSION=')) {
                final version = line.split('=').last.trim();
                if (version.isNotEmpty && !version.startsWith('#')) {
                  _logger.log('从文件系统VERSION文件（旧格式）读取最小服务器版本: $version',
                      tag: 'VERSION_COMPAT');
                  return version;
                }
              }
            }
          }

          // 检查父目录
          final parent = currentDir.parent;
          if (currentDir.path == parent.path) {
            break;
          }
          currentDir = parent;
        }
      } catch (e) {
        _logger.log('从文件系统查找VERSION.yaml失败: $e', tag: 'VERSION_COMPAT');
      }

      // 如果找不到，返回默认值（允许所有版本）
      _logger.log('未找到VERSION.yaml文件，使用默认最小服务器版本: 1.0.0',
          tag: 'VERSION_COMPAT');
      return '1.0.0';
    } catch (e, stackTrace) {
      _logger.logError('读取最小服务器版本失败', error: e, stackTrace: stackTrace);
      return '1.0.0'; // 默认允许所有版本
    }
  }
}
