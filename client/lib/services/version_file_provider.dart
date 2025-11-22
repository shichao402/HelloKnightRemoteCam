import 'dart:io';
import 'package:flutter/services.dart';
import 'logger_service.dart';

/// 版本文件提供者接口
/// 为不同平台提供读取版本文件的抽象接口
abstract class VersionFileProvider {
  /// 读取版本文件内容
  /// 返回版本文件的文本内容
  /// 如果文件不存在或读取失败，抛出异常
  Future<String> readVersionFile();

  /// 获取版本文件来源描述（用于日志）
  /// 返回描述性字符串，如 "assets/VERSION.yaml" 或文件路径
  String getSourceDescription();
}

/// Assets 版本文件提供者
/// 从 Flutter assets 读取版本文件（所有平台通用）
class AssetsVersionFileProvider extends VersionFileProvider {
  final ClientLoggerService _logger = ClientLoggerService();
  final String _assetPath;

  AssetsVersionFileProvider({String assetPath = 'assets/VERSION.yaml'})
      : _assetPath = assetPath;

  @override
  Future<String> readVersionFile() async {
    try {
      return await rootBundle.loadString(_assetPath);
    } catch (e) {
      _logger.logError('读取 assets 版本文件失败: $_assetPath', error: e);
      rethrow;
    }
  }

  @override
  String getSourceDescription() => _assetPath;
}

/// 文件系统版本文件提供者
/// 从文件系统读取版本文件（用于开发环境或特定平台）
class FileSystemVersionFileProvider extends VersionFileProvider {
  final ClientLoggerService _logger = ClientLoggerService();
  final String _filePath;

  FileSystemVersionFileProvider(this._filePath);

  @override
  Future<String> readVersionFile() async {
    final file = File(_filePath);
    if (!await file.exists()) {
      throw Exception('版本文件不存在: $_filePath');
    }
    try {
      return await file.readAsString();
    } catch (e) {
      _logger.logError('读取文件系统版本文件失败: $_filePath', error: e);
      rethrow;
    }
  }

  @override
  String getSourceDescription() => _filePath;
}

/// 版本文件提供者工厂
/// 根据平台和环境创建合适的版本文件提供者
class VersionFileProviderFactory {
  VersionFileProviderFactory._(); // 私有构造函数，防止实例化

  /// 创建默认的版本文件提供者
  /// 生产环境：使用 Assets 提供者
  /// 开发环境：如果指定了文件路径，可以使用文件系统提供者
  static VersionFileProvider createDefault({String? developmentFilePath}) {
    // 如果提供了开发文件路径，优先使用文件系统提供者（用于开发调试）
    if (developmentFilePath != null && developmentFilePath.isNotEmpty) {
      return FileSystemVersionFileProvider(developmentFilePath);
    }

    // 生产环境：所有平台都使用 Assets 提供者
    return AssetsVersionFileProvider();
  }

  /// 创建 Assets 提供者
  static VersionFileProvider createAssets(
      {String assetPath = 'assets/VERSION.yaml'}) {
    return AssetsVersionFileProvider(assetPath: assetPath);
  }

  /// 创建文件系统提供者
  static VersionFileProvider createFileSystem(String filePath) {
    return FileSystemVersionFileProvider(filePath);
  }
}
