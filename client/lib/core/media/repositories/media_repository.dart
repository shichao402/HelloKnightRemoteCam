import 'dart:async';
import '../../storage/database/app_database.dart';
import '../models/media_item.dart';
import '../models/media_type.dart';
import '../models/media_filter.dart';

/// 媒体数据仓库
/// 封装数据库操作，提供统一的数据访问接口
class MediaRepository {
  final AppDatabase _db;

  MediaRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  // ==================== 基础 CRUD ====================

  /// 插入媒体项
  Future<void> insert(MediaItem item) => _db.insertMediaItem(item);

  /// 批量插入
  Future<void> insertAll(List<MediaItem> items) async {
    for (final item in items) {
      await _db.insertMediaItem(item);
    }
  }

  /// 更新媒体项
  Future<void> update(MediaItem item) => _db.updateMediaItem(item);

  /// 删除媒体项
  Future<void> delete(String id) => _db.deleteMediaItem(id);

  /// 批量删除
  Future<void> deleteAll(List<String> ids) async {
    for (final id in ids) {
      await _db.deleteMediaItem(id);
    }
  }

  /// 获取单个媒体项
  Future<MediaItem?> getById(String id) => _db.getMediaItem(id);

  /// 检查媒体项是否存在
  Future<bool> exists(String id) async {
    final item = await _db.getMediaItem(id);
    return item != null;
  }

  /// 根据本地路径查找
  Future<MediaItem?> getByLocalPath(String localPath) async {
    final items = await _db.getAllMediaItems();
    return items.cast<MediaItem?>().firstWhere(
          (item) => item?.localPath == localPath,
          orElse: () => null,
        );
  }

  // ==================== 查询 ====================

  /// 获取所有媒体项
  Future<List<MediaItem>> getAll() => _db.getAllMediaItems();

  /// 监听所有媒体项
  Stream<List<MediaItem>> watchAll() => _db.watchAllMediaItems();

  /// 按筛选条件获取
  Future<List<MediaItem>> getFiltered(MediaFilter filter) async {
    var items = await _db.getAllMediaItems();

    // 类型筛选
    if (filter.type != null) {
      items = items.where((item) => item.type == filter.type).toList();
    }

    // 星标筛选
    if (filter.isStarred != null) {
      items = items.where((item) => item.isStarred == filter.isStarred).toList();
    }

    // 来源筛选
    if (filter.sourceId != null) {
      items = items.where((item) => item.sourceId == filter.sourceId).toList();
    }

    // 相册筛选
    if (filter.albumId != null) {
      items = items.where((item) => item.albumId == filter.albumId).toList();
    }

    // 日期范围筛选
    if (filter.startDate != null) {
      items = items.where((item) => item.createdAt.isAfter(filter.startDate!)).toList();
    }
    if (filter.endDate != null) {
      items = items.where((item) => item.createdAt.isBefore(filter.endDate!)).toList();
    }

    // 搜索筛选
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      final query = filter.searchQuery!.toLowerCase();
      items = items.where((item) => item.name.toLowerCase().contains(query)).toList();
    }

    // 标签筛选
    if (filter.tags != null && filter.tags!.isNotEmpty) {
      items = items.where((item) {
        return filter.tags!.any((tag) => item.tags.contains(tag));
      }).toList();
    }

    // 排序
    items.sort((a, b) {
      int result;
      switch (filter.sortBy) {
        case MediaSortBy.createdAt:
          result = a.createdAt.compareTo(b.createdAt);
          break;
        case MediaSortBy.modifiedAt:
          final aTime = a.modifiedAt ?? a.createdAt;
          final bTime = b.modifiedAt ?? b.createdAt;
          result = aTime.compareTo(bTime);
          break;
        case MediaSortBy.name:
          result = a.name.compareTo(b.name);
          break;
        case MediaSortBy.size:
          result = a.size.compareTo(b.size);
          break;
      }
      return filter.sortOrder == SortOrder.ascending ? result : -result;
    });

    // 分页
    if (filter.offset != null && filter.offset! > 0) {
      items = items.skip(filter.offset!).toList();
    }
    if (filter.limit != null && filter.limit! > 0) {
      items = items.take(filter.limit!).toList();
    }

    return items;
  }

  /// 获取星标媒体
  Future<List<MediaItem>> getStarred() => _db.getStarredMediaItems();

  /// 按类型获取
  Future<List<MediaItem>> getByType(MediaType type) => _db.getMediaItemsByType(type);

  /// 按来源获取
  Future<List<MediaItem>> getBySource(String sourceId) => _db.getMediaItemsBySource(sourceId);

  /// 搜索
  Future<List<MediaItem>> search(String query) => _db.searchMediaItems(query);

  // ==================== 统计 ====================

  /// 获取媒体总数
  Future<int> getCount() => _db.getMediaCount();

  /// 按类型统计
  Future<Map<MediaType, int>> getCountByType() async {
    final items = await _db.getAllMediaItems();
    final result = <MediaType, int>{};
    for (final type in MediaType.values) {
      result[type] = items.where((item) => item.type == type).length;
    }
    return result;
  }

  /// 获取总大小
  Future<int> getTotalSize() async {
    final items = await _db.getAllMediaItems();
    return items.fold<int>(0, (sum, item) => sum + item.size);
  }

  // ==================== 操作 ====================

  /// 切换星标
  Future<void> toggleStarred(String id) => _db.toggleStarred(id);

  /// 批量设置星标
  Future<void> setStarred(List<String> ids, bool starred) async {
    for (final id in ids) {
      final item = await _db.getMediaItem(id);
      if (item != null && item.isStarred != starred) {
        await _db.updateMediaItem(item.copyWith(isStarred: starred));
      }
    }
  }

  /// 添加标签
  Future<void> addTag(String id, String tag) async {
    final item = await _db.getMediaItem(id);
    if (item != null && !item.tags.contains(tag)) {
      final newTags = [...item.tags, tag];
      await _db.updateMediaItem(item.copyWith(tags: newTags));
    }
  }

  /// 移除标签
  Future<void> removeTag(String id, String tag) async {
    final item = await _db.getMediaItem(id);
    if (item != null && item.tags.contains(tag)) {
      final newTags = item.tags.where((t) => t != tag).toList();
      await _db.updateMediaItem(item.copyWith(tags: newTags));
    }
  }

  /// 设置相册
  Future<void> setAlbum(String id, String? albumId) async {
    final item = await _db.getMediaItem(id);
    if (item != null) {
      await _db.updateMediaItem(item.copyWith(albumId: albumId));
    }
  }

  /// 更新缩略图路径
  Future<void> updateThumbnailPath(String id, String thumbnailPath) async {
    final item = await _db.getMediaItem(id);
    if (item != null) {
      await _db.updateMediaItem(item.copyWith(thumbnailPath: thumbnailPath));
    }
  }
}
