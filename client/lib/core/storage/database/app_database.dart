import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';
import '../../media/models/media_item.dart' as models;
import '../../media/models/media_metadata.dart';
import '../../media/models/media_type.dart';
import '../../media/models/album.dart' as models;

part 'app_database.g.dart';

@DriftDatabase(tables: [MediaItems, Albums, MediaAlbumRelations, Tags])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // 单例模式
  static AppDatabase? _instance;
  static AppDatabase get instance {
    _instance ??= AppDatabase();
    return _instance!;
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // 创建系统相册
          await _createSystemAlbums();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // 未来版本迁移逻辑
        },
      );

  /// 创建系统相册
  Future<void> _createSystemAlbums() async {
    final now = DateTime.now();
    
    // 全部媒体相册
    await into(albums).insert(AlbumsCompanion.insert(
      id: 'system_all',
      name: '全部',
      type: const Value('all'),
      createdAt: now,
    ));

    // 星标相册
    await into(albums).insert(AlbumsCompanion.insert(
      id: 'system_starred',
      name: '星标',
      type: const Value('starred'),
      createdAt: now,
    ));
  }

  // ==================== MediaItem 操作 ====================

  /// 插入媒体项
  Future<void> insertMediaItem(models.MediaItem item) async {
    await into(mediaItems).insert(MediaItemsCompanion.insert(
      id: item.id,
      name: item.name,
      localPath: item.localPath,
      type: item.type.dbValue,
      size: item.size,
      createdAt: item.createdAt,
      modifiedAt: Value(item.modifiedAt),
      thumbnailPath: Value(item.thumbnailPath),
      metadataJson: Value(item.metadata != null ? jsonEncode(item.metadata!.toJson()) : null),
      sourceId: Value(item.sourceId),
      sourceRef: Value(item.sourceRef),
      isStarred: Value(item.isStarred),
      tagsJson: Value(jsonEncode(item.tags)),
      albumId: Value(item.albumId),
      syncStatus: Value(item.syncStatus.name),
    ));
  }

  /// 更新媒体项
  Future<void> updateMediaItem(models.MediaItem item) async {
    await (update(mediaItems)..where((t) => t.id.equals(item.id))).write(
      MediaItemsCompanion(
        name: Value(item.name),
        localPath: Value(item.localPath),
        type: Value(item.type.dbValue),
        size: Value(item.size),
        createdAt: Value(item.createdAt),
        modifiedAt: Value(item.modifiedAt),
        thumbnailPath: Value(item.thumbnailPath),
        metadataJson: Value(item.metadata != null ? jsonEncode(item.metadata!.toJson()) : null),
        sourceId: Value(item.sourceId),
        sourceRef: Value(item.sourceRef),
        isStarred: Value(item.isStarred),
        tagsJson: Value(jsonEncode(item.tags)),
        albumId: Value(item.albumId),
        syncStatus: Value(item.syncStatus.name),
      ),
    );
  }

  /// 删除媒体项
  Future<void> deleteMediaItem(String id) async {
    await (delete(mediaItems)..where((t) => t.id.equals(id))).go();
  }

  /// 获取单个媒体项
  Future<models.MediaItem?> getMediaItem(String id) async {
    final row = await (select(mediaItems)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null ? _entityToMediaItem(row) : null;
  }

  /// 获取所有媒体项
  Future<List<models.MediaItem>> getAllMediaItems() async {
    final rows = await select(mediaItems).get();
    return rows.map(_entityToMediaItem).toList();
  }

  /// 监听所有媒体项
  Stream<List<models.MediaItem>> watchAllMediaItems() {
    return select(mediaItems).watch().map((rows) => rows.map(_entityToMediaItem).toList());
  }

  /// 获取星标媒体项
  Future<List<models.MediaItem>> getStarredMediaItems() async {
    final rows = await (select(mediaItems)..where((t) => t.isStarred.equals(true))).get();
    return rows.map(_entityToMediaItem).toList();
  }

  /// 按类型获取媒体项
  Future<List<models.MediaItem>> getMediaItemsByType(MediaType type) async {
    final rows = await (select(mediaItems)..where((t) => t.type.equals(type.dbValue))).get();
    return rows.map(_entityToMediaItem).toList();
  }

  /// 搜索媒体项
  Future<List<models.MediaItem>> searchMediaItems(String query) async {
    final rows = await (select(mediaItems)..where((t) => t.name.like('%$query%'))).get();
    return rows.map(_entityToMediaItem).toList();
  }

  /// 切换星标状态
  Future<void> toggleStarred(String id) async {
    final item = await getMediaItem(id);
    if (item != null) {
      await (update(mediaItems)..where((t) => t.id.equals(id))).write(
        MediaItemsCompanion(isStarred: Value(!item.isStarred)),
      );
    }
  }

  /// 获取媒体数量
  Future<int> getMediaCount() async {
    final count = await mediaItems.count().getSingle();
    return count;
  }

  /// 按来源获取媒体项
  Future<List<models.MediaItem>> getMediaItemsBySource(String sourceId) async {
    final rows = await (select(mediaItems)..where((t) => t.sourceId.equals(sourceId))).get();
    return rows.map(_entityToMediaItem).toList();
  }

  // ==================== Album 操作 ====================

  /// 插入相册
  Future<void> insertAlbum(models.Album album) async {
    await into(albums).insert(AlbumsCompanion.insert(
      id: album.id,
      name: album.name,
      description: Value(album.description),
      type: Value(album.type.dbValue),
      coverMediaId: Value(album.coverMediaId),
      createdAt: album.createdAt,
      modifiedAt: Value(album.modifiedAt),
      mediaCount: Value(album.mediaCount),
      sourceId: Value(album.sourceId),
      smartCriteriaJson: Value(album.smartCriteria != null ? jsonEncode(album.smartCriteria) : null),
    ));
  }

  /// 更新相册
  Future<void> updateAlbum(models.Album album) async {
    await (update(albums)..where((t) => t.id.equals(album.id))).write(
      AlbumsCompanion(
        name: Value(album.name),
        description: Value(album.description),
        type: Value(album.type.dbValue),
        coverMediaId: Value(album.coverMediaId),
        modifiedAt: Value(album.modifiedAt),
        mediaCount: Value(album.mediaCount),
        sourceId: Value(album.sourceId),
        smartCriteriaJson: Value(album.smartCriteria != null ? jsonEncode(album.smartCriteria) : null),
      ),
    );
  }

  /// 删除相册
  Future<void> deleteAlbum(String id) async {
    await (delete(albums)..where((t) => t.id.equals(id))).go();
  }

  /// 获取所有相册
  Future<List<models.Album>> getAllAlbums() async {
    final rows = await select(albums).get();
    return rows.map(_entityToAlbum).toList();
  }

  /// 监听所有相册
  Stream<List<models.Album>> watchAllAlbums() {
    return select(albums).watch().map((rows) => rows.map(_entityToAlbum).toList());
  }

  /// 获取单个相册
  Future<models.Album?> getAlbum(String id) async {
    final row = await (select(albums)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null ? _entityToAlbum(row) : null;
  }

  // ==================== 辅助方法 ====================

  models.MediaItem _entityToMediaItem(MediaItemEntity row) {
    return models.MediaItem(
      id: row.id,
      name: row.name,
      localPath: row.localPath,
      type: MediaTypeExtension.fromDbValue(row.type),
      size: row.size,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
      thumbnailPath: row.thumbnailPath,
      metadata: row.metadataJson != null
          ? MediaMetadata.fromJson(jsonDecode(row.metadataJson!) as Map<String, dynamic>)
          : null,
      sourceId: row.sourceId,
      sourceRef: row.sourceRef,
      isStarred: row.isStarred,
      tags: row.tagsJson.isNotEmpty
          ? (jsonDecode(row.tagsJson) as List<dynamic>).cast<String>()
          : [],
      albumId: row.albumId,
      syncStatus: models.SyncStatus.values.firstWhere(
        (e) => e.name == row.syncStatus,
        orElse: () => models.SyncStatus.local,
      ),
    );
  }

  models.Album _entityToAlbum(AlbumEntity row) {
    return models.Album(
      id: row.id,
      name: row.name,
      description: row.description,
      type: models.AlbumTypeExtension.fromDbValue(row.type),
      coverMediaId: row.coverMediaId,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
      mediaCount: row.mediaCount,
      sourceId: row.sourceId,
      smartCriteria: row.smartCriteriaJson != null
          ? jsonDecode(row.smartCriteriaJson!) as Map<String, dynamic>
          : null,
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'HelloKnightRemoteCam', 'media_library.db'));
    
    // 确保目录存在
    await file.parent.create(recursive: true);
    
    return NativeDatabase.createInBackground(file);
  });
}
