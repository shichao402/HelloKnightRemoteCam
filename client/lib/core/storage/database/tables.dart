import 'package:drift/drift.dart';

/// 媒体项表
@DataClassName('MediaItemEntity')
class MediaItems extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get localPath => text()();
  TextColumn get type => text()(); // 'photo' | 'video'
  IntColumn get size => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get metadataJson => text().nullable()(); // JSON 存储元数据
  TextColumn get sourceId => text().nullable()();
  TextColumn get sourceRef => text().nullable()();
  BoolColumn get isStarred => boolean().withDefault(const Constant(false))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))(); // JSON 数组
  TextColumn get albumId => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 相册表
@DataClassName('AlbumEntity')
class Albums extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get type => text().withDefault(const Constant('normal'))();
  TextColumn get coverMediaId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  IntColumn get mediaCount => integer().withDefault(const Constant(0))();
  TextColumn get sourceId => text().nullable()();
  TextColumn get smartCriteriaJson => text().nullable()(); // JSON 存储智能相册条件

  @override
  Set<Column> get primaryKey => {id};
}

/// 媒体-相册关联表（支持一个媒体属于多个相册）
@DataClassName('MediaAlbumRelationEntity')
class MediaAlbumRelations extends Table {
  TextColumn get mediaId => text()();
  TextColumn get albumId => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {mediaId, albumId};
}

/// 标签表
@DataClassName('TagEntity')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  IntColumn get usageCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
