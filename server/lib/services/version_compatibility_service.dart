import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'logger_service.dart';
import 'version_service.dart';

/// 版本兼容性检查服务
/// 检查客户端版本是否符合服务器要求
class VersionCompatibilityService {
  static final VersionCompatibilityService _instance = VersionCompatibilityService._internal();
  factory VersionCompatibilityService() => _instance;
  VersionCompatibilityService._internal();

  final LoggerService _logger = LoggerService();
  final VersionService _versionService = VersionService();
  
  String? _minClientVersion;
  String? _serverVersion;

  /// 初始化（读取最小客户端版本要求）
  Future<void> initialize() async {
    try {
      _minClientVersion = await _readMinClientVersion();
      _serverVersion = await _versionService.getVersionNumber();
      _logger.log('版本兼容性服务已初始化', tag: 'VERSION_COMPAT');
      _logger.log('服务器版本: $_serverVersion, 最小客户端版本: $_minClientVersion', tag: 'VERSION_COMPAT');
    } catch (e, stackTrace) {
      _logger.logError('初始化版本兼容性服务失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 检查客户端版本是否兼容
  /// 返回 (isCompatible, reason)
  Future<(bool, String?)> checkClientVersion(String clientVersion) async {
    try {
      if (_minClientVersion == null) {
        await initialize();
      }

      if (_minClientVersion == null) {
        _logger.log('无法读取最小客户端版本要求，允许连接', tag: 'VERSION_COMPAT');
        return (true, null);
      }

      // 提取版本号部分（去掉构建号）
      final clientVersionNumber = clientVersion.split('+').first;
      
      _logger.log('检查客户端版本兼容性: 客户端=$clientVersionNumber, 要求最小版本=$_minClientVersion', tag: 'VERSION_COMPAT');

      final isCompatible = _compareVersions(clientVersionNumber, _minClientVersion!);
      
      if (!isCompatible) {
        final reason = '客户端版本 $clientVersionNumber 低于服务器要求的最小版本 $_minClientVersion';
        _logger.log('版本不兼容: $reason', tag: 'VERSION_COMPAT');
        return (false, reason);
      }

      _logger.log('客户端版本兼容', tag: 'VERSION_COMPAT');
      return (true, null);
    } catch (e, stackTrace) {
      _logger.logError('检查客户端版本失败', error: e, stackTrace: stackTrace);
      // 出错时允许连接（避免因版本检查问题导致无法连接）
      return (true, null);
    }
  }

  /// 比较版本号
  /// 返回 true 如果 version1 >= version2
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

    return true; // 相等
  }

  /// 获取服务器版本号
  Future<String> getServerVersion() async {
    _serverVersion ??= await _versionService.getVersionNumber();
    return _serverVersion!;
  }

  /// 获取最小客户端版本要求
  Future<String> getMinClientVersion() async {
    if (_minClientVersion == null) {
      await initialize();
    }
    return _minClientVersion ?? '1.0.0';
  }

  /// 从VERSION文件读取最小客户端版本要求
  Future<String?> _readMinClientVersion() async {
    try {
      // 尝试从应用文档目录向上查找项目根目录的VERSION文件
      final appDocDir = await getApplicationDocumentsDirectory();
      Directory? currentDir = Directory(appDocDir.path);
      
      // 最多向上查找10层目录
      for (int i = 0; i < 10; i++) {
        if (currentDir == null) break;
        
        final versionFile = File(path.join(currentDir.path, 'VERSION'));
        if (await versionFile.exists()) {
          final content = await versionFile.readAsString();
          final lines = content.split('\n');
          for (final line in lines) {
            if (line.trim().startsWith('MIN_CLIENT_VERSION=')) {
              final version = line.split('=').last.trim();
              if (version.isNotEmpty && !version.startsWith('#')) {
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

      // 如果找不到，返回默认值（允许所有版本）
      _logger.log('未找到VERSION文件，使用默认最小客户端版本: 1.0.0', tag: 'VERSION_COMPAT');
      return '1.0.0';
    } catch (e, stackTrace) {
      _logger.logError('读取最小客户端版本失败', error: e, stackTrace: stackTrace);
      return '1.0.0'; // 默认允许所有版本
    }
  }
}

