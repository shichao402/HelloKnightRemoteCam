import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:http/http.dart' as http;

import '../models/media_type.dart';

/// 缩略图服务
/// 负责生成、下载、缓存和管理媒体文件的缩略图
/// 统一管理本地和远端缩略图，所有缩略图都持久化存储在本地
class ThumbnailService {
  static ThumbnailService? _instance;
  static ThumbnailService get instance {
    _instance ??= ThumbnailService._();
    return _instance!;
  }

  ThumbnailService._();

  String? _thumbnailDir;
  final Map<String, String> _cache = {}; // mediaId -> thumbnailPath
  
  /// 缩略图最大缓存时间（30天）
  static const Duration maxCacheAge = Duration(days: 30);

  /// 缩略图尺寸
  static const int thumbnailSize = 256;

  /// 初始化
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _thumbnailDir = p.join(appDir.path, 'HelloKnightRemoteCam', 'thumbnails');
    await Directory(_thumbnailDir!).create(recursive: true);
    
    // 启动时清理过期缩略图
    _cleanExpiredThumbnails();
  }

  /// 获取缩略图目录
  String get thumbnailDir {
    if (_thumbnailDir == null) {
      throw StateError('ThumbnailService not initialized. Call init() first.');
    }
    return _thumbnailDir!;
  }

  /// 从远端URL下载缩略图并持久化存储
  /// [remoteUrl] 远端缩略图URL
  /// [cacheKey] 缓存键（通常是远端路径的hash）
  /// 返回本地缩略图路径
  Future<String?> downloadAndCache(String remoteUrl, String cacheKey) async {
    try {
      if (_thumbnailDir == null) await init();

      final hash = _generateHash(cacheKey);
      final thumbnailPath = p.join(_thumbnailDir!, '$hash.jpg');

      // 如果已存在且未过期，直接返回
      final file = File(thumbnailPath);
      if (await file.exists()) {
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified);
        if (age < maxCacheAge) {
          return thumbnailPath;
        }
      }

      // 下载缩略图
      debugPrint('[ThumbnailService] Downloading thumbnail: $remoteUrl');
      final response = await http.get(Uri.parse(remoteUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('Timeout', 408),
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[ThumbnailService] Thumbnail saved: $thumbnailPath');
        return thumbnailPath;
      } else {
        debugPrint('[ThumbnailService] Failed to download thumbnail: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error downloading thumbnail: $e');
      return null;
    }
  }

  /// 获取缩略图路径（优先使用已缓存的）
  /// [cacheKey] 缓存键
  Future<String?> getCachedPath(String cacheKey) async {
    if (_thumbnailDir == null) await init();
    
    final hash = _generateHash(cacheKey);
    final thumbnailPath = p.join(_thumbnailDir!, '$hash.jpg');
    
    final file = File(thumbnailPath);
    if (await file.exists()) {
      return thumbnailPath;
    }
    return null;
  }

  /// 生成本地文件的缩略图
  /// 返回缩略图路径
  Future<String?> generate(String mediaPath, MediaType type) async {
    try {
      if (_thumbnailDir == null) await init();

      final file = File(mediaPath);
      if (!await file.exists()) {
        debugPrint('[ThumbnailService] File not found: $mediaPath');
        return null;
      }

      // 生成唯一的缩略图文件名
      final hash = _generateHash(mediaPath);
      final thumbnailPath = p.join(_thumbnailDir!, '$hash.jpg');

      // 如果缩略图已存在，直接返回
      if (await File(thumbnailPath).exists()) {
        return thumbnailPath;
      }

      // 根据类型生成缩略图
      if (type == MediaType.photo) {
        return await _generateImageThumbnail(mediaPath, thumbnailPath);
      } else {
        return await _generateVideoThumbnail(mediaPath, thumbnailPath);
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error generating thumbnail: $e');
      return null;
    }
  }

  /// 生成图片缩略图
  Future<String?> _generateImageThumbnail(String imagePath, String outputPath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final resized = await compute(_resizeImage, _ResizeParams(bytes, thumbnailSize));
      
      if (resized != null) {
        await File(outputPath).writeAsBytes(resized);
        return outputPath;
      }
      return null;
    } catch (e) {
      debugPrint('[ThumbnailService] Error generating image thumbnail: $e');
      return null;
    }
  }

  /// 生成视频缩略图
  Future<String?> _generateVideoThumbnail(String videoPath, String outputPath) async {
    try {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: outputPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: thumbnailSize,
        quality: 75,
      );
      
      if (thumbnailPath != null && await File(thumbnailPath).exists()) {
        debugPrint('[ThumbnailService] Video thumbnail generated: $thumbnailPath');
        return thumbnailPath;
      }
      
      debugPrint('[ThumbnailService] Video thumbnail generation returned null');
      return null;
    } catch (e) {
      debugPrint('[ThumbnailService] Error generating video thumbnail: $e');
      return null;
    }
  }

  /// 获取缩略图路径（兼容旧接口）
  Future<String?> get(String mediaId, String mediaPath, MediaType type) async {
    // 先检查缓存
    if (_cache.containsKey(mediaId)) {
      final cached = _cache[mediaId]!;
      if (await File(cached).exists()) {
        return cached;
      }
      _cache.remove(mediaId);
    }

    // 检查是否已生成
    final hash = _generateHash(mediaPath);
    final thumbnailPath = p.join(thumbnailDir, '$hash.jpg');
    if (await File(thumbnailPath).exists()) {
      _cache[mediaId] = thumbnailPath;
      return thumbnailPath;
    }

    // 生成新的缩略图
    final generated = await generate(mediaPath, type);
    if (generated != null) {
      _cache[mediaId] = generated;
    }
    return generated;
  }

  /// 删除缩略图
  Future<void> delete(String cacheKey) async {
    try {
      final hash = _generateHash(cacheKey);
      final thumbnailPath = p.join(thumbnailDir, '$hash.jpg');
      final file = File(thumbnailPath);
      if (await file.exists()) {
        await file.delete();
      }
      // 从缓存中移除
      _cache.removeWhere((_, path) => path == thumbnailPath);
    } catch (e) {
      debugPrint('[ThumbnailService] Error deleting thumbnail: $e');
    }
  }

  /// 清理过期缩略图
  Future<void> _cleanExpiredThumbnails() async {
    try {
      final dir = Directory(thumbnailDir);
      if (!await dir.exists()) return;

      final now = DateTime.now();
      int deletedCount = 0;

      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          if (age > maxCacheAge) {
            await entity.delete();
            deletedCount++;
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('[ThumbnailService] Cleaned $deletedCount expired thumbnails');
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error cleaning expired thumbnails: $e');
    }
  }

  /// 清理所有缩略图缓存
  Future<void> clearCache() async {
    try {
      _cache.clear();
      final dir = Directory(thumbnailDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error clearing cache: $e');
    }
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    try {
      final dir = Directory(thumbnailDir);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// 格式化缓存大小
  Future<String> getFormattedCacheSize() async {
    final size = await getCacheSize();
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(2)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 生成文件路径的哈希值
  String _generateHash(String path) {
    final bytes = utf8.encode(path);
    final digest = md5.convert(bytes);
    return digest.toString();
  }
}

/// 图片缩放参数
class _ResizeParams {
  final Uint8List bytes;
  final int targetSize;

  _ResizeParams(this.bytes, this.targetSize);
}

/// 在 isolate 中缩放图片
Future<Uint8List?> _resizeImage(_ResizeParams params) async {
  try {
    final codec = await ui.instantiateImageCodec(
      params.bytes,
      targetWidth: params.targetSize,
      targetHeight: params.targetSize,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (e) {
    return null;
  }
}
