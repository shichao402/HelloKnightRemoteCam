import 'media_type.dart';

/// 媒体排序方式
enum MediaSortBy {
  createdAt,
  modifiedAt,
  name,
  size,
}

/// 排序方向
enum SortOrder {
  ascending,
  descending,
}

/// 媒体筛选条件
class MediaFilter {
  final MediaType? type;            // 按类型筛选
  final String? albumId;            // 按相册筛选
  final String? sourceId;           // 按来源筛选
  final bool? isStarred;            // 按星标筛选
  final List<String>? tags;         // 按标签筛选（任意匹配）
  final DateTime? startDate;        // 开始日期
  final DateTime? endDate;          // 结束日期
  final String? searchQuery;        // 搜索关键词
  final MediaSortBy sortBy;         // 排序字段
  final SortOrder sortOrder;        // 排序方向
  final int? limit;                 // 限制数量
  final int? offset;                // 偏移量

  const MediaFilter({
    this.type,
    this.albumId,
    this.sourceId,
    this.isStarred,
    this.tags,
    this.startDate,
    this.endDate,
    this.searchQuery,
    this.sortBy = MediaSortBy.createdAt,
    this.sortOrder = SortOrder.descending,
    this.limit,
    this.offset,
  });

  /// 默认筛选器（全部媒体，按创建时间倒序）
  static const MediaFilter defaultFilter = MediaFilter();

  /// 仅照片
  static const MediaFilter photosOnly = MediaFilter(type: MediaType.photo);

  /// 仅视频
  static const MediaFilter videosOnly = MediaFilter(type: MediaType.video);

  /// 仅星标
  static const MediaFilter starredOnly = MediaFilter(isStarred: true);

  MediaFilter copyWith({
    MediaType? type,
    String? albumId,
    String? sourceId,
    bool? isStarred,
    List<String>? tags,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    MediaSortBy? sortBy,
    SortOrder? sortOrder,
    int? limit,
    int? offset,
  }) {
    return MediaFilter(
      type: type ?? this.type,
      albumId: albumId ?? this.albumId,
      sourceId: sourceId ?? this.sourceId,
      isStarred: isStarred ?? this.isStarred,
      tags: tags ?? this.tags,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  /// 清除某个筛选条件
  MediaFilter clearType() => copyWith()._withNullType();
  MediaFilter clearAlbum() => copyWith()._withNullAlbum();
  MediaFilter clearSource() => copyWith()._withNullSource();
  MediaFilter clearStarred() => copyWith()._withNullStarred();
  MediaFilter clearTags() => copyWith()._withNullTags();
  MediaFilter clearDateRange() => copyWith()._withNullDateRange();
  MediaFilter clearSearch() => copyWith()._withNullSearch();

  MediaFilter _withNullType() => MediaFilter(
        albumId: albumId,
        sourceId: sourceId,
        isStarred: isStarred,
        tags: tags,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit,
        offset: offset,
      );

  MediaFilter _withNullAlbum() => MediaFilter(
        type: type,
        sourceId: sourceId,
        isStarred: isStarred,
        tags: tags,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit,
        offset: offset,
      );

  MediaFilter _withNullSource() => MediaFilter(
        type: type,
        albumId: albumId,
        isStarred: isStarred,
        tags: tags,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit,
        offset: offset,
      );

  MediaFilter _withNullStarred() => MediaFilter(
        type: type,
        albumId: albumId,
        sourceId: sourceId,
        tags: tags,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit,
        offset: offset,
      );

  MediaFilter _withNullTags() => MediaFilter(
        type: type,
        albumId: albumId,
        sourceId: sourceId,
        isStarred: isStarred,
        startDate: startDate,
        endDate: endDate,
        searchQuery: searchQuery,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit,
        offset: offset,
      );

  MediaFilter _withNullDateRange() => MediaFilter(
        type: type,
        albumId: albumId,
        sourceId: sourceId,
        isStarred: isStarred,
        tags: tags,
        searchQuery: searchQuery,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit,
        offset: offset,
      );

  MediaFilter _withNullSearch() => MediaFilter(
        type: type,
        albumId: albumId,
        sourceId: sourceId,
        isStarred: isStarred,
        tags: tags,
        startDate: startDate,
        endDate: endDate,
        sortBy: sortBy,
        sortOrder: sortOrder,
        limit: limit,
        offset: offset,
      );

  @override
  String toString() =>
      'MediaFilter(type: $type, albumId: $albumId, isStarred: $isStarred, sortBy: $sortBy)';
}
