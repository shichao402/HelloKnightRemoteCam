import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import '../models/media_type.dart';
import '../models/media_filter.dart';
import '../models/album.dart';
import '../repositories/media_repository.dart';
import '../repositories/album_repository.dart';
import 'thumbnail_service.dart';
import 'import_service.dart';
import '../../../models/file_info.dart';

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
  /// - 云端文件（pending 状态）：从数据库删除，刷新后重新出现
  /// - 本地文件有云端来源：删除本地文件，状态退化为 pending（云端文件）
  /// - 纯本地文件：完全删除
  Future<void> deleteMedia(String id) async {
    _ensureInitialized();
    final item = await _mediaRepository.getById(id);
    if (item != null) {
      if (item.syncStatus == SyncStatus.pending) {
        // 云端文件（未下载）：只从数据库删除，用户可通过刷新重新同步
        await _mediaRepository.delete(id);
        debugPrint('[MediaLibraryService] Removed remote file from library: ${item.name}');
      } else if (item.sourceRef != null && item.sourceRef!.isNotEmpty) {
        // 已下载的云端文件：删除本地文件，状态退化为 pending
        await _importService.deleteLocalFileOnly(item);
        // 更新状态为 pending（云端未下载）
        final degradedItem = item.copyWith(
          localPath: '',
          thumbnailPath: null,
          syncStatus: SyncStatus.pending,
        );
        await _mediaRepository.update(degradedItem);
        debugPrint('[MediaLibraryService] Degraded to remote file: ${item.name}');
      } else {
        // 纯本地文件：完全删除
        await _importService.deleteMediaFile(item);
        debugPrint('[MediaLibraryService] Deleted local file: ${item.name}');
      }
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

  // ==================== 云端同步 ====================

  /// 同步云端文件到本地媒体库
  /// - 新文件：添加到数据库并下载缩略图
  /// - 已存在但无缩略图：补充下载缩略图
  /// [remoteFiles] 云端文件列表
  /// [baseUrl] 服务器基础URL，用于下载缩略图
  /// 返回新增的云端文件数量
  Future<int> syncRemoteFiles(
    List<FileInfo> remoteFiles, {
    String? baseUrl,
  }) async {
    _ensureInitialized();
    
    if (remoteFiles.isEmpty) {
      debugPrint('[MediaLibraryService] No remote files to sync');
      return 0;
    }
    
    debugPrint('[MediaLibraryService] Syncing ${remoteFiles.length} remote files');
    
    // 获取本地所有媒体项，建立 sourceRef -> MediaItem 的映射
    final localMedia = await _mediaRepository.getAll();
    final Map<String, MediaItem> localBySourceRef = {};
    final Map<String, MediaItem> localByName = {};
    
    for (final m in localMedia) {
      if (m.sourceRef != null) {
        localBySourceRef[m.sourceRef!] = m;
      }
      localByName[m.name] = m;
    }
    
    int addedCount = 0;
    int thumbnailUpdatedCount = 0;
    
    for (final remoteFile in remoteFiles) {
      // 检查是否已存在
      MediaItem? existingItem = localBySourceRef[remoteFile.path] ?? localByName[remoteFile.name];
      
      if (existingItem != null) {
        // 已存在：检查是否需要补充缩略图
        if (baseUrl != null && (existingItem.thumbnailPath == null || existingItem.thumbnailPath!.isEmpty)) {
          final thumbnailFile = existingItem.thumbnailPath != null && existingItem.thumbnailPath!.isNotEmpty
              ? File(existingItem.thumbnailPath!)
              : null;
          final thumbnailExists = thumbnailFile != null && await thumbnailFile.exists();
          
          if (!thumbnailExists) {
            // 下载缩略图
            final typeStr = remoteFile.isVideo ? 'video' : 'image';
            final thumbnailUrl = '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remoteFile.path)}&type=$typeStr';
            final thumbnailPath = await _thumbnailService.downloadAndCache(thumbnailUrl, remoteFile.path);
            
            if (thumbnailPath != null) {
              final updatedItem = existingItem.copyWith(thumbnailPath: thumbnailPath);
              await _mediaRepository.update(updatedItem);
              thumbnailUpdatedCount++;
              debugPrint('[MediaLibraryService] Updated thumbnail for: ${existingItem.name}');
            }
          }
        }
        continue;
      }
      
      // 新文件：创建云端媒体项（pending 状态）
      final type = remoteFile.isVideo ? MediaType.video : MediaType.photo;
      final id = 'remote_${DateTime.now().millisecondsSinceEpoch}_${remoteFile.name.hashCode}';
      
      // 下载并持久化缩略图
      String? thumbnailPath;
      if (baseUrl != null) {
        final typeStr = remoteFile.isVideo ? 'video' : 'image';
        final thumbnailUrl = '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remoteFile.path)}&type=$typeStr';
        thumbnailPath = await _thumbnailService.downloadAndCache(thumbnailUrl, remoteFile.path);
      }
      
      final mediaItem = MediaItem(
        id: id,
        name: remoteFile.name,
        localPath: '', // 云端文件没有本地路径
        type: type,
        size: remoteFile.size,
        createdAt: remoteFile.createdTime,
        modifiedAt: remoteFile.modifiedTime,
        sourceRef: remoteFile.path, // 远程路径
        thumbnailPath: thumbnailPath, // 持久化的缩略图路径
        isStarred: remoteFile.isStarred,
        syncStatus: SyncStatus.pending, // 标记为待下载
      );
      
      await _mediaRepository.insert(mediaItem);
      addedCount++;
      
      debugPrint('[MediaLibraryService] Added remote file: ${remoteFile.name}, thumbnail: ${thumbnailPath != null}');
    }
    
    debugPrint('[MediaLibraryService] Sync completed, added $addedCount files, updated $thumbnailUpdatedCount thumbnails');
    return addedCount;
  }

  /// 清除所有云端文件（pending 状态的文件）
  /// 断开连接时调用
  Future<int> clearRemoteFiles() async {
    _ensureInitialized();
    
    final allMedia = await _mediaRepository.getAll();
    final pendingMedia = allMedia.where((m) => m.syncStatus == SyncStatus.pending).toList();
    
    for (final item in pendingMedia) {
      await _mediaRepository.delete(item.id);
    }
    
    debugPrint('[MediaLibraryService] Cleared ${pendingMedia.length} remote files');
    return pendingMedia.length;
  }

  /// 将云端文件标记为已下载（更新为 synced 状态）
  /// 优先复用已有缩略图，没有时才从本地文件生成
  Future<void> markAsDownloaded(String mediaId, String localPath) async {
    _ensureInitialized();
    
    final item = await _mediaRepository.getById(mediaId);
    if (item != null && item.syncStatus == SyncStatus.pending) {
      String? thumbnailPath = item.thumbnailPath;
      
      // 检查已有缩略图是否有效
      bool hasValidThumbnail = false;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        hasValidThumbnail = await File(thumbnailPath).exists();
      }
      
      // 只有没有有效缩略图时才生成
      if (!hasValidThumbnail) {
        thumbnailPath = await _thumbnailService.generate(localPath, item.type);
        debugPrint('[MediaLibraryService] Generated thumbnail for: ${item.name}');
      } else {
        debugPrint('[MediaLibraryService] Reusing existing thumbnail for: ${item.name}');
      }
      
      final updatedItem = item.copyWith(
        localPath: localPath,
        thumbnailPath: thumbnailPath,
        syncStatus: SyncStatus.synced,
      );
      await _mediaRepository.update(updatedItem);
      debugPrint('[MediaLibraryService] Marked as downloaded: ${item.name}');
    }
  }

  // ==================== 清理 ====================

  /// 释放资源
  void dispose() {
    _mediaStreamController.close();
    _albumStreamController.close();
  }
}
