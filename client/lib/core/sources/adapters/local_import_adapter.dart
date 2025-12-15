import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../base/sources_base.dart';
import '../../media/services/media_library_service.dart';
import '../../../services/logger_service.dart';

/// 本地导入配置
class LocalImportConfig implements SourceConfig {
  @override
  final String id;

  @override
  final String name;

  @override
  SourceType get type => SourceType.localImport;

  /// 默认导入目录（可选）
  final String? defaultImportPath;

  const LocalImportConfig({
    this.id = 'local_import',
    this.name = '本地导入',
    this.defaultImportPath,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        if (defaultImportPath != null) 'defaultImportPath': defaultImportPath,
      };
}

/// 本地导入适配器
///
/// 用于从本地文件系统导入媒体文件
class LocalImportAdapter implements SourceAdapter {
  final LocalImportConfig config;
  final MediaLibraryService _libraryService;
  final ClientLoggerService _logger = ClientLoggerService();

  SourceStatus _status = SourceStatus.connected; // 本地导入始终可用
  SourceError? _lastError;

  final _statusController = StreamController<SourceStatus>.broadcast();

  LocalImportAdapter({
    required this.config,
    required MediaLibraryService libraryService,
  }) : _libraryService = libraryService;

  // ==================== SourceAdapter 实现 ====================

  @override
  String get id => config.id;

  @override
  String get name => config.name;

  @override
  SourceType get type => SourceType.localImport;

  @override
  SourceStatus get status => _status;

  @override
  Stream<SourceStatus> get statusStream => _statusController.stream;

  @override
  SourceError? get lastError => _lastError;

  @override
  bool get isConnected => true; // 本地导入始终可用

  @override
  Future<void> connect() async {
    // 本地导入不需要连接
    _status = SourceStatus.connected;
    _statusController.add(_status);
  }

  @override
  Future<void> disconnect() async {
    // 本地导入不需要断开
  }

  @override
  void dispose() {
    _statusController.close();
  }

  // ==================== 导入方法 ====================

  /// 导入单个文件
  Future<LocalImportResult> importFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return LocalImportResult(
          success: false,
          error: '文件不存在: $filePath',
        );
      }

      final mediaItem = await _libraryService.importFile(filePath, sourceId: id);
      if (mediaItem != null) {
        _logger.log('导入文件成功: $filePath', tag: 'LOCAL_IMPORT');
        return LocalImportResult(
          success: true,
          importedCount: 1,
          mediaItem: mediaItem,
        );
      } else {
        return LocalImportResult(
          success: false,
          error: '导入失败',
        );
      }
    } catch (e) {
      _logger.logError('导入文件失败', error: e);
      _lastError = SourceError.fromException(e);
      return LocalImportResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// 批量导入文件
  Future<LocalImportResult> importFiles(List<String> filePaths) async {
    int successCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    for (final filePath in filePaths) {
      try {
        final file = File(filePath);
        if (!await file.exists()) {
          failedCount++;
          errors.add('文件不存在: $filePath');
          continue;
        }

        final mediaItem = await _libraryService.importFile(filePath, sourceId: id);
        if (mediaItem != null) {
          successCount++;
        } else {
          failedCount++;
          errors.add('导入失败: $filePath');
        }
      } catch (e) {
        failedCount++;
        errors.add('$filePath: $e');
      }
    }

    _logger.log('批量导入完成: 成功 $successCount, 失败 $failedCount', tag: 'LOCAL_IMPORT');

    return LocalImportResult(
      success: failedCount == 0,
      importedCount: successCount,
      failedCount: failedCount,
      errors: errors,
    );
  }

  /// 导入目录
  Future<LocalImportResult> importDirectory(
    String directoryPath, {
    bool recursive = true,
  }) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return LocalImportResult(
          success: false,
          error: '目录不存在: $directoryPath',
        );
      }

      final filePaths = <String>[];
      final supportedExtensions = [
        '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif',
        '.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v',
      ];

      await for (final entity in directory.list(recursive: recursive)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (supportedExtensions.contains(ext)) {
            filePaths.add(entity.path);
          }
        }
      }

      if (filePaths.isEmpty) {
        return LocalImportResult(
          success: true,
          importedCount: 0,
          error: '目录中没有支持的媒体文件',
        );
      }

      return await importFiles(filePaths);
    } catch (e) {
      _logger.logError('导入目录失败', error: e);
      _lastError = SourceError.fromException(e);
      return LocalImportResult(
        success: false,
        error: e.toString(),
      );
    }
  }
}

/// 本地导入结果
class LocalImportResult {
  final bool success;
  final int importedCount;
  final int failedCount;
  final String? error;
  final List<String> errors;
  final dynamic mediaItem;

  const LocalImportResult({
    required this.success,
    this.importedCount = 0,
    this.failedCount = 0,
    this.error,
    this.errors = const [],
    this.mediaItem,
  });
}
