import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import '../models/media_type.dart';
import '../models/media_filter.dart';
import '../models/album.dart';
import '../repositories/media_repository.dart';
import '../repositories/album_repository.dart';
import 'thumbnail_service.dart';
import 'import_service.dart';

/// 媒体库统计信息
class MediaLibraryStats {
  final int totalCount;
  final int photoCount;
  final int videoCount;
  final int starredCount;
  final int totalSize;
  final int albumCount;

  MediaLibraryStats({
    required this.totalCount,
    required this.photoCount,
    required this.videoCount,
    required this.starredCount,
    required this.totalSize,
    required this.albumCount,
  });

  String get formattedTotalSize {
    if (totalSize < 1024) {
      return '$totalSize B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(2)} KB';
    } else if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}

/// 媒体库核心服务
/// 统一管理媒体项、相册、导入导出等功能
class MediaLibraryService {
  static MediaLibraryService? _instance;
  static MediaLibraryService get instance {
    _instance ??= MediaLibraryService._();
    return _instance!;
  }

  MediaLibraryService._();

  late final MediaRepository _mediaRepository;
  late final AlbumRepository _albumRepository;
  late final ThumbnailService _thumbnailService;
  late final ImportService _importService;

  bool _initialized = false;

  // 媒体变化通知
  final _mediaStreamController = StreamController<List<MediaItem>>.broadcast();
  Stream<List<MediaItem>> get mediaStream => _mediaStreamController.stream;

  // 相册变化通知
  final _albumStreamController = StreamController<List<Album>>.broadcast();
  Stream<List<Album>> get albumStream => _albumStreamController.stream;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    debugPrint('[MediaLibraryService] Initializing...');

    _mediaRepository = MediaRepository();
    _albumRepository = AlbumRepository();
    _thumbnailService = ThumbnailService.instance;
    _importService = ImportService(
      mediaRepository: _mediaRepository,
      thumbnailService: _thumbnailService,
    );

    await _thumbnailService.init();
    await _importService.init();

    // 监听数据库变化
    _mediaRepository.watchAll().listen((items) {
      _mediaStreamController.add(items);
    });

    _albumRepository.watchAll().listen((albums) {
      _albumStreamController.add(albums);
    });

    _initialized = true;
    debugPrint('[MediaLibraryService] Initialized');
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('MediaLibraryService not initialized. Call init() first.');
    }
  }

  // ==================== 媒体项操作 ====================

  /// 获取所有媒体项
  Future<List<MediaItem>> getAllMedia() async {
    _ensureInitialized();
    return _mediaRepository.getAll();
  }

  /// 按筛选条件获取媒体项
  Future<List<MediaItem>> getMedia(MediaFilter filter) async {
    _ensureInitialized();
    return _mediaRepository.getFiltered(filter);
  }

  /// 获取单个媒体项
  Future<MediaItem?> getMediaById(String id) async {
    _ensureInitialized();
    return _mediaRepository.getById(id);
  }

  /// 搜索媒体
  Future<List<MediaItem>> searchMedia(String query) async {
    _ensureInitialized();
    return _mediaRepository.search(query);
  }

  /// 获取星标媒体
  Future<List<MediaItem>> getStarredMedia() async {
    _ensureInitialized();
    return _mediaRepository.getStarred();
  }

  /// 按类型获取媒体
  Future<List<MediaItem>> getMediaByType(MediaType type) async {
    _ensureInitialized();
    return _mediaRepository.getByType(type);
  }

  /// 切换星标状态
  Future<void> toggleStarred(String id) async {
    _ensureInitialized();
    await _mediaRepository.toggleStarred(id);
  }

  /// 批量设置星标
  Future<void> setStarred(List<String> ids, bool starred) async {
    _ensureInitialized();
    await _mediaRepository.setStarred(ids, starred);
  }

  /// 删除媒体项
  Future<void> deleteMedia(String id) async {
    _ensureInitialized();
    final item = await _mediaRepository.getById(id);
    if (item != null) {
      await _importService.deleteMediaFile(item);
    }
  }

  /// 批量删除媒体项
  Future<void> deleteMediaBatch(List<String> ids) async {
    _ensureInitialized();
    for (final id in ids) {
      await deleteMedia(id);
    }
  }

  /// 添加标签
  Future<void> addTag(String mediaId, String tag) async {
    _ensureInitialized();
    await _mediaRepository.addTag(mediaId, tag);
  }

  /// 移除标签
  Future<void> removeTag(String mediaId, String tag) async {
    _ensureInitialized();
    await _mediaRepository.removeTag(mediaId, tag);
  }

  // ==================== 导入操作 ====================

  /// 导入单个文件
  Future<ImportResult> importFile(
    String filePath, {
    String? sourceId,
    String? sourceRef,
    bool copyFile = true,
  }) async {
    _ensureInitialized();
    return _importService.importFile(
      filePath,
      sourceId: sourceId,
      sourceRef: sourceRef,
      copyFile: copyFile,
    );
  }

  /// 批量导入文件
  Stream<ImportProgress> importFiles(
    List<String> filePaths, {
    String? sourceId,
    bool copyFile = true,
  }) {
    _ensureInitialized();
    return _importService.importFiles(
      filePaths,
      sourceId: sourceId,
      copyFile: copyFile,
    );
  }

  /// 导入目录
  Stream<ImportProgress> importDirectory(
    String directoryPath, {
    String? sourceId,
    bool copyFile = true,
    bool recursive = true,
  }) {
    _ensureInitialized();
    return _importService.importDirectory(
      directoryPath,
      sourceId: sourceId,
      copyFile: copyFile,
      recursive: recursive,
    );
  }

  // ==================== 相册操作 ====================

  /// 获取所有相册
  Future<List<Album>> getAllAlbums() async {
    _ensureInitialized();
    return _albumRepository.getAll();
  }

  /// 获取用户相册（排除系统相册）
  Future<List<Album>> getUserAlbums() async {
    _ensureInitialized();
    return _albumRepository.getUserAlbums();
  }

  /// 创建相册
  Future<Album> createAlbum(String name, {String? description}) async {
    _ensureInitialized();
    final album = Album(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      type: AlbumType.normal,
      createdAt: DateTime.now(),
    );
    await _albumRepository.insert(album);
    return album;
  }

  /// 删除相册
  Future<void> deleteAlbum(String albumId) async {
    _ensureInitialized();
    final album = await _albumRepository.getById(albumId);
    if (album != null && !album.isSystem) {
      await _albumRepository.delete(albumId);
    }
  }

  /// 重命名相册
  Future<void> renameAlbum(String albumId, String newName) async {
    _ensureInitialized();
    await _albumRepository.rename(albumId, newName);
  }

  /// 添加媒体到相册
  Future<void> addToAlbum(String mediaId, String albumId) async {
    _ensureInitialized();
    await _mediaRepository.setAlbum(mediaId, albumId);
    // 更新相册媒体数量
    await _updateAlbumMediaCount(albumId);
  }

  /// 从相册移除媒体
  Future<void> removeFromAlbum(String mediaId) async {
    _ensureInitialized();
    final item = await _mediaRepository.getById(mediaId);
    if (item != null && item.albumId != null) {
      final albumId = item.albumId!;
      await _mediaRepository.setAlbum(mediaId, null);
      await _updateAlbumMediaCount(albumId);
    }
  }

  /// 获取相册中的媒体
  Future<List<MediaItem>> getAlbumMedia(String albumId) async {
    _ensureInitialized();
    return _mediaRepository.getFiltered(MediaFilter(albumId: albumId));
  }

  /// 更新相册媒体数量
  Future<void> _updateAlbumMediaCount(String albumId) async {
    final media = await getAlbumMedia(albumId);
    await _albumRepository.updateMediaCount(albumId, media.length);
    
    // 更新封面（使用第一个媒体）
    if (media.isNotEmpty) {
      await _albumRepository.updateCover(albumId, media.first.id);
    } else {
      await _albumRepository.updateCover(albumId, null);
    }
  }

  // ==================== 统计信息 ====================

  /// 获取媒体库统计信息
  Future<MediaLibraryStats> getStats() async {
    _ensureInitialized();
    
    final allMedia = await _mediaRepository.getAll();
    final albums = await _albumRepository.getUserAlbums();
    
    return MediaLibraryStats(
      totalCount: allMedia.length,
      photoCount: allMedia.where((m) => m.type == MediaType.photo).length,
      videoCount: allMedia.where((m) => m.type == MediaType.video).length,
      starredCount: allMedia.where((m) => m.isStarred).length,
      totalSize: allMedia.fold<int>(0, (sum, m) => sum + m.size),
      albumCount: albums.length,
    );
  }

  // ==================== 缩略图 ====================

  /// 获取缩略图路径
  Future<String?> getThumbnail(MediaItem item) async {
    _ensureInitialized();
    if (item.thumbnailPath != null) {
      return item.thumbnailPath;
    }
    return _thumbnailService.get(item.id, item.localPath, item.type);
  }

  /// 清理缩略图缓存
  Future<void> clearThumbnailCache() async {
    _ensureInitialized();
    await _thumbnailService.clearCache();
  }

  /// 获取缩略图缓存大小
  Future<String> getThumbnailCacheSize() async {
    _ensureInitialized();
    return _thumbnailService.getFormattedCacheSize();
  }

  // ==================== 清理 ====================

  /// 释放资源
  void dispose() {
    _mediaStreamController.close();
    _albumStreamController.close();
  }
}
