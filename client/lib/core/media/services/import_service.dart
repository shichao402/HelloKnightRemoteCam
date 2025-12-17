import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../models/media_item.dart';
import '../models/media_type.dart';
import '../models/media_metadata.dart';
import '../repositories/media_repository.dart';
import 'thumbnail_service.dart';

/// 导入结果
class ImportResult {
  final bool success;
  final MediaItem? mediaItem;
  final String? error;

  ImportResult.success(this.mediaItem)
      : success = true,
        error = null;

  ImportResult.failure(this.error)
      : success = false,
        mediaItem = null;
}

/// 批量导入进度
class ImportProgress {
  final int total;
  final int completed;
  final int failed;
  final String? currentFile;

  ImportProgress({
    required this.total,
    required this.completed,
    required this.failed,
    this.currentFile,
  });

  double get progress => total > 0 ? completed / total : 0;
}

/// 媒体导入服务
/// 负责将外部文件导入到本地媒体库
class ImportService {
  final MediaRepository _mediaRepository;
  final ThumbnailService _thumbnailService;

  String? _mediaDir;

  ImportService({
    MediaRepository? mediaRepository,
    ThumbnailService? thumbnailService,
  })  : _mediaRepository = mediaRepository ?? MediaRepository(),
        _thumbnailService = thumbnailService ?? ThumbnailService.instance;

  /// 初始化
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _mediaDir = p.join(appDir.path, 'HelloKnightRemoteCam', 'media');
    await Directory(_mediaDir!).create(recursive: true);
    await _thumbnailService.init();
  }

  /// 获取媒体存储目录
  String get mediaDir {
    if (_mediaDir == null) {
      throw StateError('ImportService not initialized. Call init() first.');
    }
    return _mediaDir!;
  }

  /// 导入单个文件
  /// [sourcePath] 源文件路径
  /// [sourceId] 数据源ID（可选）
  /// [sourceRef] 数据源引用（可选）
  /// [copyFile] 是否复制文件到媒体库目录，false 则只建立索引
  Future<ImportResult> importFile(
    String sourcePath, {
    String? sourceId,
    String? sourceRef,
    bool copyFile = true,
  }) async {
    try {
      if (_mediaDir == null) await init();

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return ImportResult.failure('文件不存在: $sourcePath');
      }

      // 获取文件信息
      final stat = await sourceFile.stat();
      final fileName = p.basename(sourcePath);
      final extension = p.extension(sourcePath);
      final type = MediaTypeExtension.fromExtension(extension);

      // 生成唯一ID
      final id = _generateId(sourcePath, stat.modified);

      // 检查是否已存在
      final existing = await _mediaRepository.getById(id);
      if (existing != null) {
        return ImportResult.success(existing);
      }

      // 确定目标路径
      String localPath;
      if (copyFile) {
        localPath = await _copyToMediaDir(sourceFile, type, stat.modified);
      } else {
        localPath = sourcePath;
      }

      // 生成缩略图
      final thumbnailPath = await _thumbnailService.generate(localPath, type);

      // 提取元数据
      final metadata = await _extractMetadata(localPath, type);

      // 创建媒体项
      final mediaItem = MediaItem(
        id: id,
        name: fileName,
        localPath: localPath,
        type: type,
        size: stat.size,
        createdAt: stat.modified,
        modifiedAt: stat.modified,
        thumbnailPath: thumbnailPath,
        metadata: metadata,
        sourceId: sourceId,
        sourceRef: sourceRef ?? sourcePath,
        syncStatus: SyncStatus.local,
      );

      // 保存到数据库
      await _mediaRepository.insert(mediaItem);

      debugPrint('[ImportService] Imported: $fileName');
      return ImportResult.success(mediaItem);
    } catch (e) {
      debugPrint('[ImportService] Error importing file: $e');
      return ImportResult.failure('导入失败: $e');
    }
  }

  /// 批量导入文件
  Stream<ImportProgress> importFiles(
    List<String> sourcePaths, {
    String? sourceId,
    bool copyFile = true,
  }) async* {
    if (_mediaDir == null) await init();

    int completed = 0;
    int failed = 0;
    final total = sourcePaths.length;

    for (final path in sourcePaths) {
      yield ImportProgress(
        total: total,
        completed: completed,
        failed: failed,
        currentFile: p.basename(path),
      );

      final result = await importFile(
        path,
        sourceId: sourceId,
        copyFile: copyFile,
      );

      if (result.success) {
        completed++;
      } else {
        failed++;
      }
    }

    yield ImportProgress(
      total: total,
      completed: completed,
      failed: failed,
    );
  }

  /// 从目录导入所有媒体文件
  Stream<ImportProgress> importDirectory(
    String directoryPath, {
    String? sourceId,
    bool copyFile = true,
    bool recursive = true,
  }) async* {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      yield ImportProgress(total: 0, completed: 0, failed: 0);
      return;
    }

    // 收集所有媒体文件
    final files = <String>[];
    await for (final entity in dir.list(recursive: recursive)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (_isSupportedExtension(ext)) {
          files.add(entity.path);
        }
      }
    }

    yield* importFiles(files, sourceId: sourceId, copyFile: copyFile);
  }

  /// 复制文件到媒体目录
  Future<String> _copyToMediaDir(File sourceFile, MediaType type, DateTime date) async {
    // 按日期组织目录结构
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final subDir = type == MediaType.video ? 'videos' : 'photos';
    
    final targetDir = p.join(_mediaDir!, subDir, year, month);
    await Directory(targetDir).create(recursive: true);

    // 生成唯一文件名（避免冲突）
    final fileName = p.basename(sourceFile.path);
    var targetPath = p.join(targetDir, fileName);
    
    // 如果文件已存在，添加时间戳
    if (await File(targetPath).exists()) {
      final nameWithoutExt = p.basenameWithoutExtension(fileName);
      final ext = p.extension(fileName);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      targetPath = p.join(targetDir, '${nameWithoutExt}_$timestamp$ext');
    }

    // 复制文件
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  /// 提取媒体元数据
  Future<MediaMetadata?> _extractMetadata(String filePath, MediaType type) async {
    // TODO: 实现元数据提取
    // 对于图片：使用 exif 包读取 EXIF 信息
    // 对于视频：使用 ffprobe 或 video_player 获取信息
    return null;
  }

  /// 生成唯一ID
  String _generateId(String path, DateTime modified) {
    final input = '$path:${modified.millisecondsSinceEpoch}';
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// 检查是否为支持的文件扩展名
  bool _isSupportedExtension(String ext) {
    const supported = {
      // 图片
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.bmp',
      // 视频
      '.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp',
    };
    return supported.contains(ext.toLowerCase());
  }

  /// 删除媒体文件（包括缩略图）
  Future<void> deleteMediaFile(MediaItem item) async {
    try {
      // 删除原文件（仅当文件在媒体目录内时）
      if (item.localPath.startsWith(_mediaDir ?? '')) {
        final file = File(item.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // 删除缩略图
      await _thumbnailService.delete(item.localPath);

      // 从数据库删除
      await _mediaRepository.delete(item.id);

      debugPrint('[ImportService] Deleted: ${item.name}');
    } catch (e) {
      debugPrint('[ImportService] Error deleting media: $e');
      rethrow;
    }
  }

  /// 仅删除本地文件和缩略图，不删除数据库记录
  /// 用于将已下载的云端文件退化为 pending 状态
  Future<void> deleteLocalFileOnly(MediaItem item) async {
    try {
      // 删除原文件（仅当文件在媒体目录内时）
      if (item.localPath.isNotEmpty && item.localPath.startsWith(_mediaDir ?? '')) {
        final file = File(item.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // 删除缩略图
      if (item.localPath.isNotEmpty) {
        await _thumbnailService.delete(item.localPath);
      }

      debugPrint('[ImportService] Deleted local files only: ${item.name}');
    } catch (e) {
      debugPrint('[ImportService] Error deleting local files: $e');
      rethrow;
    }
  }
}
