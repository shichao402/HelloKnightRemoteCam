// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MediaItemsTable extends MediaItems
    with TableInfo<$MediaItemsTable, MediaItemEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localPathMeta =
      const VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
      'local_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
      'size', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _modifiedAtMeta =
      const VerificationMeta('modifiedAt');
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
      'modified_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _thumbnailPathMeta =
      const VerificationMeta('thumbnailPath');
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
      'thumbnail_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _metadataJsonMeta =
      const VerificationMeta('metadataJson');
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
      'metadata_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceRefMeta =
      const VerificationMeta('sourceRef');
  @override
  late final GeneratedColumn<String> sourceRef = GeneratedColumn<String>(
      'source_ref', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isStarredMeta =
      const VerificationMeta('isStarred');
  @override
  late final GeneratedColumn<bool> isStarred = GeneratedColumn<bool>(
      'is_starred', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_starred" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _tagsJsonMeta =
      const VerificationMeta('tagsJson');
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
      'tags_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _albumIdMeta =
      const VerificationMeta('albumId');
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
      'album_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncStatusMeta =
      const VerificationMeta('syncStatus');
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
      'sync_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        localPath,
        type,
        size,
        createdAt,
        modifiedAt,
        thumbnailPath,
        metadataJson,
        sourceId,
        sourceRef,
        isStarred,
        tagsJson,
        albumId,
        syncStatus
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_items';
  @override
  VerificationContext validateIntegrity(Insertable<MediaItemEntity> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta,
          localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
          _sizeMeta, size.isAcceptableOrUnknown(data['size']!, _sizeMeta));
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
          _modifiedAtMeta,
          modifiedAt.isAcceptableOrUnknown(
              data['modified_at']!, _modifiedAtMeta));
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
          _thumbnailPathMeta,
          thumbnailPath.isAcceptableOrUnknown(
              data['thumbnail_path']!, _thumbnailPathMeta));
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
          _metadataJsonMeta,
          metadataJson.isAcceptableOrUnknown(
              data['metadata_json']!, _metadataJsonMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    }
    if (data.containsKey('source_ref')) {
      context.handle(_sourceRefMeta,
          sourceRef.isAcceptableOrUnknown(data['source_ref']!, _sourceRefMeta));
    }
    if (data.containsKey('is_starred')) {
      context.handle(_isStarredMeta,
          isStarred.isAcceptableOrUnknown(data['is_starred']!, _isStarredMeta));
    }
    if (data.containsKey('tags_json')) {
      context.handle(_tagsJsonMeta,
          tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta));
    }
    if (data.containsKey('album_id')) {
      context.handle(_albumIdMeta,
          albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta));
    }
    if (data.containsKey('sync_status')) {
      context.handle(
          _syncStatusMeta,
          syncStatus.isAcceptableOrUnknown(
              data['sync_status']!, _syncStatusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaItemEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaItemEntity(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      localPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_path'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      size: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      modifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}modified_at']),
      thumbnailPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_path']),
      metadataJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata_json']),
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id']),
      sourceRef: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_ref']),
      isStarred: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_starred'])!,
      tagsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags_json'])!,
      albumId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album_id']),
      syncStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_status'])!,
    );
  }

  @override
  $MediaItemsTable createAlias(String alias) {
    return $MediaItemsTable(attachedDatabase, alias);
  }
}

class MediaItemEntity extends DataClass implements Insertable<MediaItemEntity> {
  final String id;
  final String name;
  final String localPath;
  final String type;
  final int size;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final String? thumbnailPath;
  final String? metadataJson;
  final String? sourceId;
  final String? sourceRef;
  final bool isStarred;
  final String tagsJson;
  final String? albumId;
  final String syncStatus;
  const MediaItemEntity(
      {required this.id,
      required this.name,
      required this.localPath,
      required this.type,
      required this.size,
      required this.createdAt,
      this.modifiedAt,
      this.thumbnailPath,
      this.metadataJson,
      this.sourceId,
      this.sourceRef,
      required this.isStarred,
      required this.tagsJson,
      this.albumId,
      required this.syncStatus});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['local_path'] = Variable<String>(localPath);
    map['type'] = Variable<String>(type);
    map['size'] = Variable<int>(size);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || modifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(modifiedAt);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || sourceRef != null) {
      map['source_ref'] = Variable<String>(sourceRef);
    }
    map['is_starred'] = Variable<bool>(isStarred);
    map['tags_json'] = Variable<String>(tagsJson);
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<String>(albumId);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  MediaItemsCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsCompanion(
      id: Value(id),
      name: Value(name),
      localPath: Value(localPath),
      type: Value(type),
      size: Value(size),
      createdAt: Value(createdAt),
      modifiedAt: modifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(modifiedAt),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      sourceRef: sourceRef == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceRef),
      isStarred: Value(isStarred),
      tagsJson: Value(tagsJson),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      syncStatus: Value(syncStatus),
    );
  }

  factory MediaItemEntity.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaItemEntity(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      localPath: serializer.fromJson<String>(json['localPath']),
      type: serializer.fromJson<String>(json['type']),
      size: serializer.fromJson<int>(json['size']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime?>(json['modifiedAt']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      sourceRef: serializer.fromJson<String?>(json['sourceRef']),
      isStarred: serializer.fromJson<bool>(json['isStarred']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      albumId: serializer.fromJson<String?>(json['albumId']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'localPath': serializer.toJson<String>(localPath),
      'type': serializer.toJson<String>(type),
      'size': serializer.toJson<int>(size),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime?>(modifiedAt),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'sourceId': serializer.toJson<String?>(sourceId),
      'sourceRef': serializer.toJson<String?>(sourceRef),
      'isStarred': serializer.toJson<bool>(isStarred),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'albumId': serializer.toJson<String?>(albumId),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  MediaItemEntity copyWith(
          {String? id,
          String? name,
          String? localPath,
          String? type,
          int? size,
          DateTime? createdAt,
          Value<DateTime?> modifiedAt = const Value.absent(),
          Value<String?> thumbnailPath = const Value.absent(),
          Value<String?> metadataJson = const Value.absent(),
          Value<String?> sourceId = const Value.absent(),
          Value<String?> sourceRef = const Value.absent(),
          bool? isStarred,
          String? tagsJson,
          Value<String?> albumId = const Value.absent(),
          String? syncStatus}) =>
      MediaItemEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        localPath: localPath ?? this.localPath,
        type: type ?? this.type,
        size: size ?? this.size,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt.present ? modifiedAt.value : this.modifiedAt,
        thumbnailPath:
            thumbnailPath.present ? thumbnailPath.value : this.thumbnailPath,
        metadataJson:
            metadataJson.present ? metadataJson.value : this.metadataJson,
        sourceId: sourceId.present ? sourceId.value : this.sourceId,
        sourceRef: sourceRef.present ? sourceRef.value : this.sourceRef,
        isStarred: isStarred ?? this.isStarred,
        tagsJson: tagsJson ?? this.tagsJson,
        albumId: albumId.present ? albumId.value : this.albumId,
        syncStatus: syncStatus ?? this.syncStatus,
      );
  MediaItemEntity copyWithCompanion(MediaItemsCompanion data) {
    return MediaItemEntity(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      type: data.type.present ? data.type.value : this.type,
      size: data.size.present ? data.size.value : this.size,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceRef: data.sourceRef.present ? data.sourceRef.value : this.sourceRef,
      isStarred: data.isStarred.present ? data.isStarred.value : this.isStarred,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemEntity(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('localPath: $localPath, ')
          ..write('type: $type, ')
          ..write('size: $size, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceRef: $sourceRef, ')
          ..write('isStarred: $isStarred, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('albumId: $albumId, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      localPath,
      type,
      size,
      createdAt,
      modifiedAt,
      thumbnailPath,
      metadataJson,
      sourceId,
      sourceRef,
      isStarred,
      tagsJson,
      albumId,
      syncStatus);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItemEntity &&
          other.id == this.id &&
          other.name == this.name &&
          other.localPath == this.localPath &&
          other.type == this.type &&
          other.size == this.size &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.thumbnailPath == this.thumbnailPath &&
          other.metadataJson == this.metadataJson &&
          other.sourceId == this.sourceId &&
          other.sourceRef == this.sourceRef &&
          other.isStarred == this.isStarred &&
          other.tagsJson == this.tagsJson &&
          other.albumId == this.albumId &&
          other.syncStatus == this.syncStatus);
}

class MediaItemsCompanion extends UpdateCompanion<MediaItemEntity> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> localPath;
  final Value<String> type;
  final Value<int> size;
  final Value<DateTime> createdAt;
  final Value<DateTime?> modifiedAt;
  final Value<String?> thumbnailPath;
  final Value<String?> metadataJson;
  final Value<String?> sourceId;
  final Value<String?> sourceRef;
  final Value<bool> isStarred;
  final Value<String> tagsJson;
  final Value<String?> albumId;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const MediaItemsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.localPath = const Value.absent(),
    this.type = const Value.absent(),
    this.size = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceRef = const Value.absent(),
    this.isStarred = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.albumId = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaItemsCompanion.insert({
    required String id,
    required String name,
    required String localPath,
    required String type,
    required int size,
    required DateTime createdAt,
    this.modifiedAt = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceRef = const Value.absent(),
    this.isStarred = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.albumId = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        localPath = Value(localPath),
        type = Value(type),
        size = Value(size),
        createdAt = Value(createdAt);
  static Insertable<MediaItemEntity> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? localPath,
    Expression<String>? type,
    Expression<int>? size,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<String>? thumbnailPath,
    Expression<String>? metadataJson,
    Expression<String>? sourceId,
    Expression<String>? sourceRef,
    Expression<bool>? isStarred,
    Expression<String>? tagsJson,
    Expression<String>? albumId,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (localPath != null) 'local_path': localPath,
      if (type != null) 'type': type,
      if (size != null) 'size': size,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceRef != null) 'source_ref': sourceRef,
      if (isStarred != null) 'is_starred': isStarred,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (albumId != null) 'album_id': albumId,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? localPath,
      Value<String>? type,
      Value<int>? size,
      Value<DateTime>? createdAt,
      Value<DateTime?>? modifiedAt,
      Value<String?>? thumbnailPath,
      Value<String?>? metadataJson,
      Value<String?>? sourceId,
      Value<String?>? sourceRef,
      Value<bool>? isStarred,
      Value<String>? tagsJson,
      Value<String?>? albumId,
      Value<String>? syncStatus,
      Value<int>? rowid}) {
    return MediaItemsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      type: type ?? this.type,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      metadataJson: metadataJson ?? this.metadataJson,
      sourceId: sourceId ?? this.sourceId,
      sourceRef: sourceRef ?? this.sourceRef,
      isStarred: isStarred ?? this.isStarred,
      tagsJson: tagsJson ?? this.tagsJson,
      albumId: albumId ?? this.albumId,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceRef.present) {
      map['source_ref'] = Variable<String>(sourceRef.value);
    }
    if (isStarred.present) {
      map['is_starred'] = Variable<bool>(isStarred.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('localPath: $localPath, ')
          ..write('type: $type, ')
          ..write('size: $size, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceRef: $sourceRef, ')
          ..write('isStarred: $isStarred, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('albumId: $albumId, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumsTable extends Albums with TableInfo<$AlbumsTable, AlbumEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('normal'));
  static const VerificationMeta _coverMediaIdMeta =
      const VerificationMeta('coverMediaId');
  @override
  late final GeneratedColumn<String> coverMediaId = GeneratedColumn<String>(
      'cover_media_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _modifiedAtMeta =
      const VerificationMeta('modifiedAt');
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
      'modified_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _mediaCountMeta =
      const VerificationMeta('mediaCount');
  @override
  late final GeneratedColumn<int> mediaCount = GeneratedColumn<int>(
      'media_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _smartCriteriaJsonMeta =
      const VerificationMeta('smartCriteriaJson');
  @override
  late final GeneratedColumn<String> smartCriteriaJson =
      GeneratedColumn<String>('smart_criteria_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        description,
        type,
        coverMediaId,
        createdAt,
        modifiedAt,
        mediaCount,
        sourceId,
        smartCriteriaJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(Insertable<AlbumEntity> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('cover_media_id')) {
      context.handle(
          _coverMediaIdMeta,
          coverMediaId.isAcceptableOrUnknown(
              data['cover_media_id']!, _coverMediaIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
          _modifiedAtMeta,
          modifiedAt.isAcceptableOrUnknown(
              data['modified_at']!, _modifiedAtMeta));
    }
    if (data.containsKey('media_count')) {
      context.handle(
          _mediaCountMeta,
          mediaCount.isAcceptableOrUnknown(
              data['media_count']!, _mediaCountMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    }
    if (data.containsKey('smart_criteria_json')) {
      context.handle(
          _smartCriteriaJsonMeta,
          smartCriteriaJson.isAcceptableOrUnknown(
              data['smart_criteria_json']!, _smartCriteriaJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlbumEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumEntity(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      coverMediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cover_media_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      modifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}modified_at']),
      mediaCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}media_count'])!,
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id']),
      smartCriteriaJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}smart_criteria_json']),
    );
  }

  @override
  $AlbumsTable createAlias(String alias) {
    return $AlbumsTable(attachedDatabase, alias);
  }
}

class AlbumEntity extends DataClass implements Insertable<AlbumEntity> {
  final String id;
  final String name;
  final String? description;
  final String type;
  final String? coverMediaId;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final int mediaCount;
  final String? sourceId;
  final String? smartCriteriaJson;
  const AlbumEntity(
      {required this.id,
      required this.name,
      this.description,
      required this.type,
      this.coverMediaId,
      required this.createdAt,
      this.modifiedAt,
      required this.mediaCount,
      this.sourceId,
      this.smartCriteriaJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || coverMediaId != null) {
      map['cover_media_id'] = Variable<String>(coverMediaId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || modifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(modifiedAt);
    }
    map['media_count'] = Variable<int>(mediaCount);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || smartCriteriaJson != null) {
      map['smart_criteria_json'] = Variable<String>(smartCriteriaJson);
    }
    return map;
  }

  AlbumsCompanion toCompanion(bool nullToAbsent) {
    return AlbumsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      type: Value(type),
      coverMediaId: coverMediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverMediaId),
      createdAt: Value(createdAt),
      modifiedAt: modifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(modifiedAt),
      mediaCount: Value(mediaCount),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      smartCriteriaJson: smartCriteriaJson == null && nullToAbsent
          ? const Value.absent()
          : Value(smartCriteriaJson),
    );
  }

  factory AlbumEntity.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumEntity(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      type: serializer.fromJson<String>(json['type']),
      coverMediaId: serializer.fromJson<String?>(json['coverMediaId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime?>(json['modifiedAt']),
      mediaCount: serializer.fromJson<int>(json['mediaCount']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      smartCriteriaJson:
          serializer.fromJson<String?>(json['smartCriteriaJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'type': serializer.toJson<String>(type),
      'coverMediaId': serializer.toJson<String?>(coverMediaId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime?>(modifiedAt),
      'mediaCount': serializer.toJson<int>(mediaCount),
      'sourceId': serializer.toJson<String?>(sourceId),
      'smartCriteriaJson': serializer.toJson<String?>(smartCriteriaJson),
    };
  }

  AlbumEntity copyWith(
          {String? id,
          String? name,
          Value<String?> description = const Value.absent(),
          String? type,
          Value<String?> coverMediaId = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> modifiedAt = const Value.absent(),
          int? mediaCount,
          Value<String?> sourceId = const Value.absent(),
          Value<String?> smartCriteriaJson = const Value.absent()}) =>
      AlbumEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description.present ? description.value : this.description,
        type: type ?? this.type,
        coverMediaId:
            coverMediaId.present ? coverMediaId.value : this.coverMediaId,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt.present ? modifiedAt.value : this.modifiedAt,
        mediaCount: mediaCount ?? this.mediaCount,
        sourceId: sourceId.present ? sourceId.value : this.sourceId,
        smartCriteriaJson: smartCriteriaJson.present
            ? smartCriteriaJson.value
            : this.smartCriteriaJson,
      );
  AlbumEntity copyWithCompanion(AlbumsCompanion data) {
    return AlbumEntity(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      type: data.type.present ? data.type.value : this.type,
      coverMediaId: data.coverMediaId.present
          ? data.coverMediaId.value
          : this.coverMediaId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      mediaCount:
          data.mediaCount.present ? data.mediaCount.value : this.mediaCount,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      smartCriteriaJson: data.smartCriteriaJson.present
          ? data.smartCriteriaJson.value
          : this.smartCriteriaJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumEntity(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('type: $type, ')
          ..write('coverMediaId: $coverMediaId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('mediaCount: $mediaCount, ')
          ..write('sourceId: $sourceId, ')
          ..write('smartCriteriaJson: $smartCriteriaJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, description, type, coverMediaId,
      createdAt, modifiedAt, mediaCount, sourceId, smartCriteriaJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumEntity &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.type == this.type &&
          other.coverMediaId == this.coverMediaId &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.mediaCount == this.mediaCount &&
          other.sourceId == this.sourceId &&
          other.smartCriteriaJson == this.smartCriteriaJson);
}

class AlbumsCompanion extends UpdateCompanion<AlbumEntity> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> type;
  final Value<String?> coverMediaId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> modifiedAt;
  final Value<int> mediaCount;
  final Value<String?> sourceId;
  final Value<String?> smartCriteriaJson;
  final Value<int> rowid;
  const AlbumsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.type = const Value.absent(),
    this.coverMediaId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.mediaCount = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.smartCriteriaJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.type = const Value.absent(),
    this.coverMediaId = const Value.absent(),
    required DateTime createdAt,
    this.modifiedAt = const Value.absent(),
    this.mediaCount = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.smartCriteriaJson = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<AlbumEntity> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? type,
    Expression<String>? coverMediaId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<int>? mediaCount,
    Expression<String>? sourceId,
    Expression<String>? smartCriteriaJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (type != null) 'type': type,
      if (coverMediaId != null) 'cover_media_id': coverMediaId,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (mediaCount != null) 'media_count': mediaCount,
      if (sourceId != null) 'source_id': sourceId,
      if (smartCriteriaJson != null) 'smart_criteria_json': smartCriteriaJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? description,
      Value<String>? type,
      Value<String?>? coverMediaId,
      Value<DateTime>? createdAt,
      Value<DateTime?>? modifiedAt,
      Value<int>? mediaCount,
      Value<String?>? sourceId,
      Value<String?>? smartCriteriaJson,
      Value<int>? rowid}) {
    return AlbumsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      coverMediaId: coverMediaId ?? this.coverMediaId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      mediaCount: mediaCount ?? this.mediaCount,
      sourceId: sourceId ?? this.sourceId,
      smartCriteriaJson: smartCriteriaJson ?? this.smartCriteriaJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (coverMediaId.present) {
      map['cover_media_id'] = Variable<String>(coverMediaId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (mediaCount.present) {
      map['media_count'] = Variable<int>(mediaCount.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (smartCriteriaJson.present) {
      map['smart_criteria_json'] = Variable<String>(smartCriteriaJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('type: $type, ')
          ..write('coverMediaId: $coverMediaId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('mediaCount: $mediaCount, ')
          ..write('sourceId: $sourceId, ')
          ..write('smartCriteriaJson: $smartCriteriaJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaAlbumRelationsTable extends MediaAlbumRelations
    with TableInfo<$MediaAlbumRelationsTable, MediaAlbumRelationEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaAlbumRelationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _albumIdMeta =
      const VerificationMeta('albumId');
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
      'album_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [mediaId, albumId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_album_relations';
  @override
  VerificationContext validateIntegrity(
      Insertable<MediaAlbumRelationEntity> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('album_id')) {
      context.handle(_albumIdMeta,
          albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta));
    } else if (isInserting) {
      context.missing(_albumIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId, albumId};
  @override
  MediaAlbumRelationEntity map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaAlbumRelationEntity(
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      albumId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album_id'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $MediaAlbumRelationsTable createAlias(String alias) {
    return $MediaAlbumRelationsTable(attachedDatabase, alias);
  }
}

class MediaAlbumRelationEntity extends DataClass
    implements Insertable<MediaAlbumRelationEntity> {
  final String mediaId;
  final String albumId;
  final DateTime addedAt;
  const MediaAlbumRelationEntity(
      {required this.mediaId, required this.albumId, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['album_id'] = Variable<String>(albumId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  MediaAlbumRelationsCompanion toCompanion(bool nullToAbsent) {
    return MediaAlbumRelationsCompanion(
      mediaId: Value(mediaId),
      albumId: Value(albumId),
      addedAt: Value(addedAt),
    );
  }

  factory MediaAlbumRelationEntity.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaAlbumRelationEntity(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      albumId: serializer.fromJson<String>(json['albumId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'albumId': serializer.toJson<String>(albumId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  MediaAlbumRelationEntity copyWith(
          {String? mediaId, String? albumId, DateTime? addedAt}) =>
      MediaAlbumRelationEntity(
        mediaId: mediaId ?? this.mediaId,
        albumId: albumId ?? this.albumId,
        addedAt: addedAt ?? this.addedAt,
      );
  MediaAlbumRelationEntity copyWithCompanion(
      MediaAlbumRelationsCompanion data) {
    return MediaAlbumRelationEntity(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaAlbumRelationEntity(')
          ..write('mediaId: $mediaId, ')
          ..write('albumId: $albumId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaId, albumId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaAlbumRelationEntity &&
          other.mediaId == this.mediaId &&
          other.albumId == this.albumId &&
          other.addedAt == this.addedAt);
}

class MediaAlbumRelationsCompanion
    extends UpdateCompanion<MediaAlbumRelationEntity> {
  final Value<String> mediaId;
  final Value<String> albumId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const MediaAlbumRelationsCompanion({
    this.mediaId = const Value.absent(),
    this.albumId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaAlbumRelationsCompanion.insert({
    required String mediaId,
    required String albumId,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  })  : mediaId = Value(mediaId),
        albumId = Value(albumId),
        addedAt = Value(addedAt);
  static Insertable<MediaAlbumRelationEntity> custom({
    Expression<String>? mediaId,
    Expression<String>? albumId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (albumId != null) 'album_id': albumId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaAlbumRelationsCompanion copyWith(
      {Value<String>? mediaId,
      Value<String>? albumId,
      Value<DateTime>? addedAt,
      Value<int>? rowid}) {
    return MediaAlbumRelationsCompanion(
      mediaId: mediaId ?? this.mediaId,
      albumId: albumId ?? this.albumId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaAlbumRelationsCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('albumId: $albumId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _usageCountMeta =
      const VerificationMeta('usageCount');
  @override
  late final GeneratedColumn<int> usageCount = GeneratedColumn<int>(
      'usage_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, name, usageCount, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(Insertable<TagEntity> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('usage_count')) {
      context.handle(
          _usageCountMeta,
          usageCount.isAcceptableOrUnknown(
              data['usage_count']!, _usageCountMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagEntity(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      usageCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}usage_count'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagEntity extends DataClass implements Insertable<TagEntity> {
  final String id;
  final String name;
  final int usageCount;
  final DateTime createdAt;
  const TagEntity(
      {required this.id,
      required this.name,
      required this.usageCount,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['usage_count'] = Variable<int>(usageCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      usageCount: Value(usageCount),
      createdAt: Value(createdAt),
    );
  }

  factory TagEntity.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagEntity(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      usageCount: serializer.fromJson<int>(json['usageCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'usageCount': serializer.toJson<int>(usageCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TagEntity copyWith(
          {String? id, String? name, int? usageCount, DateTime? createdAt}) =>
      TagEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        usageCount: usageCount ?? this.usageCount,
        createdAt: createdAt ?? this.createdAt,
      );
  TagEntity copyWithCompanion(TagsCompanion data) {
    return TagEntity(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      usageCount:
          data.usageCount.present ? data.usageCount.value : this.usageCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagEntity(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('usageCount: $usageCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, usageCount, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagEntity &&
          other.id == this.id &&
          other.name == this.name &&
          other.usageCount == this.usageCount &&
          other.createdAt == this.createdAt);
}

class TagsCompanion extends UpdateCompanion<TagEntity> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> usageCount;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.usageCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    this.usageCount = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<TagEntity> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? usageCount,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (usageCount != null) 'usage_count': usageCount,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? usageCount,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (usageCount.present) {
      map['usage_count'] = Variable<int>(usageCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('usageCount: $usageCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MediaItemsTable mediaItems = $MediaItemsTable(this);
  late final $AlbumsTable albums = $AlbumsTable(this);
  late final $MediaAlbumRelationsTable mediaAlbumRelations =
      $MediaAlbumRelationsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [mediaItems, albums, mediaAlbumRelations, tags];
}

typedef $$MediaItemsTableCreateCompanionBuilder = MediaItemsCompanion Function({
  required String id,
  required String name,
  required String localPath,
  required String type,
  required int size,
  required DateTime createdAt,
  Value<DateTime?> modifiedAt,
  Value<String?> thumbnailPath,
  Value<String?> metadataJson,
  Value<String?> sourceId,
  Value<String?> sourceRef,
  Value<bool> isStarred,
  Value<String> tagsJson,
  Value<String?> albumId,
  Value<String> syncStatus,
  Value<int> rowid,
});
typedef $$MediaItemsTableUpdateCompanionBuilder = MediaItemsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> localPath,
  Value<String> type,
  Value<int> size,
  Value<DateTime> createdAt,
  Value<DateTime?> modifiedAt,
  Value<String?> thumbnailPath,
  Value<String?> metadataJson,
  Value<String?> sourceId,
  Value<String?> sourceRef,
  Value<bool> isStarred,
  Value<String> tagsJson,
  Value<String?> albumId,
  Value<String> syncStatus,
  Value<int> rowid,
});

class $$MediaItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get size => $composableBuilder(
      column: $table.size, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceRef => $composableBuilder(
      column: $table.sourceRef, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isStarred => $composableBuilder(
      column: $table.isStarred, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get albumId => $composableBuilder(
      column: $table.albumId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnFilters(column));
}

class $$MediaItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get size => $composableBuilder(
      column: $table.size, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceRef => $composableBuilder(
      column: $table.sourceRef, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isStarred => $composableBuilder(
      column: $table.isStarred, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get albumId => $composableBuilder(
      column: $table.albumId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
}

class $$MediaItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceRef =>
      $composableBuilder(column: $table.sourceRef, builder: (column) => column);

  GeneratedColumn<bool> get isStarred =>
      $composableBuilder(column: $table.isStarred, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => column);
}

class $$MediaItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MediaItemsTable,
    MediaItemEntity,
    $$MediaItemsTableFilterComposer,
    $$MediaItemsTableOrderingComposer,
    $$MediaItemsTableAnnotationComposer,
    $$MediaItemsTableCreateCompanionBuilder,
    $$MediaItemsTableUpdateCompanionBuilder,
    (
      MediaItemEntity,
      BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItemEntity>
    ),
    MediaItemEntity,
    PrefetchHooks Function()> {
  $$MediaItemsTableTableManager(_$AppDatabase db, $MediaItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> localPath = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> size = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> modifiedAt = const Value.absent(),
            Value<String?> thumbnailPath = const Value.absent(),
            Value<String?> metadataJson = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> sourceRef = const Value.absent(),
            Value<bool> isStarred = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<String?> albumId = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaItemsCompanion(
            id: id,
            name: name,
            localPath: localPath,
            type: type,
            size: size,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            thumbnailPath: thumbnailPath,
            metadataJson: metadataJson,
            sourceId: sourceId,
            sourceRef: sourceRef,
            isStarred: isStarred,
            tagsJson: tagsJson,
            albumId: albumId,
            syncStatus: syncStatus,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String localPath,
            required String type,
            required int size,
            required DateTime createdAt,
            Value<DateTime?> modifiedAt = const Value.absent(),
            Value<String?> thumbnailPath = const Value.absent(),
            Value<String?> metadataJson = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> sourceRef = const Value.absent(),
            Value<bool> isStarred = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<String?> albumId = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaItemsCompanion.insert(
            id: id,
            name: name,
            localPath: localPath,
            type: type,
            size: size,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            thumbnailPath: thumbnailPath,
            metadataJson: metadataJson,
            sourceId: sourceId,
            sourceRef: sourceRef,
            isStarred: isStarred,
            tagsJson: tagsJson,
            albumId: albumId,
            syncStatus: syncStatus,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MediaItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MediaItemsTable,
    MediaItemEntity,
    $$MediaItemsTableFilterComposer,
    $$MediaItemsTableOrderingComposer,
    $$MediaItemsTableAnnotationComposer,
    $$MediaItemsTableCreateCompanionBuilder,
    $$MediaItemsTableUpdateCompanionBuilder,
    (
      MediaItemEntity,
      BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItemEntity>
    ),
    MediaItemEntity,
    PrefetchHooks Function()>;
typedef $$AlbumsTableCreateCompanionBuilder = AlbumsCompanion Function({
  required String id,
  required String name,
  Value<String?> description,
  Value<String> type,
  Value<String?> coverMediaId,
  required DateTime createdAt,
  Value<DateTime?> modifiedAt,
  Value<int> mediaCount,
  Value<String?> sourceId,
  Value<String?> smartCriteriaJson,
  Value<int> rowid,
});
typedef $$AlbumsTableUpdateCompanionBuilder = AlbumsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> description,
  Value<String> type,
  Value<String?> coverMediaId,
  Value<DateTime> createdAt,
  Value<DateTime?> modifiedAt,
  Value<int> mediaCount,
  Value<String?> sourceId,
  Value<String?> smartCriteriaJson,
  Value<int> rowid,
});

class $$AlbumsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get coverMediaId => $composableBuilder(
      column: $table.coverMediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mediaCount => $composableBuilder(
      column: $table.mediaCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get smartCriteriaJson => $composableBuilder(
      column: $table.smartCriteriaJson,
      builder: (column) => ColumnFilters(column));
}

class $$AlbumsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get coverMediaId => $composableBuilder(
      column: $table.coverMediaId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mediaCount => $composableBuilder(
      column: $table.mediaCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get smartCriteriaJson => $composableBuilder(
      column: $table.smartCriteriaJson,
      builder: (column) => ColumnOrderings(column));
}

class $$AlbumsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get coverMediaId => $composableBuilder(
      column: $table.coverMediaId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => column);

  GeneratedColumn<int> get mediaCount => $composableBuilder(
      column: $table.mediaCount, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get smartCriteriaJson => $composableBuilder(
      column: $table.smartCriteriaJson, builder: (column) => column);
}

class $$AlbumsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AlbumsTable,
    AlbumEntity,
    $$AlbumsTableFilterComposer,
    $$AlbumsTableOrderingComposer,
    $$AlbumsTableAnnotationComposer,
    $$AlbumsTableCreateCompanionBuilder,
    $$AlbumsTableUpdateCompanionBuilder,
    (AlbumEntity, BaseReferences<_$AppDatabase, $AlbumsTable, AlbumEntity>),
    AlbumEntity,
    PrefetchHooks Function()> {
  $$AlbumsTableTableManager(_$AppDatabase db, $AlbumsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String?> coverMediaId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> modifiedAt = const Value.absent(),
            Value<int> mediaCount = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> smartCriteriaJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumsCompanion(
            id: id,
            name: name,
            description: description,
            type: type,
            coverMediaId: coverMediaId,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            mediaCount: mediaCount,
            sourceId: sourceId,
            smartCriteriaJson: smartCriteriaJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> description = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String?> coverMediaId = const Value.absent(),
            required DateTime createdAt,
            Value<DateTime?> modifiedAt = const Value.absent(),
            Value<int> mediaCount = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> smartCriteriaJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumsCompanion.insert(
            id: id,
            name: name,
            description: description,
            type: type,
            coverMediaId: coverMediaId,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            mediaCount: mediaCount,
            sourceId: sourceId,
            smartCriteriaJson: smartCriteriaJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AlbumsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AlbumsTable,
    AlbumEntity,
    $$AlbumsTableFilterComposer,
    $$AlbumsTableOrderingComposer,
    $$AlbumsTableAnnotationComposer,
    $$AlbumsTableCreateCompanionBuilder,
    $$AlbumsTableUpdateCompanionBuilder,
    (AlbumEntity, BaseReferences<_$AppDatabase, $AlbumsTable, AlbumEntity>),
    AlbumEntity,
    PrefetchHooks Function()>;
typedef $$MediaAlbumRelationsTableCreateCompanionBuilder
    = MediaAlbumRelationsCompanion Function({
  required String mediaId,
  required String albumId,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$MediaAlbumRelationsTableUpdateCompanionBuilder
    = MediaAlbumRelationsCompanion Function({
  Value<String> mediaId,
  Value<String> albumId,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$MediaAlbumRelationsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaAlbumRelationsTable> {
  $$MediaAlbumRelationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get albumId => $composableBuilder(
      column: $table.albumId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$MediaAlbumRelationsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaAlbumRelationsTable> {
  $$MediaAlbumRelationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get albumId => $composableBuilder(
      column: $table.albumId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$MediaAlbumRelationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaAlbumRelationsTable> {
  $$MediaAlbumRelationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$MediaAlbumRelationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MediaAlbumRelationsTable,
    MediaAlbumRelationEntity,
    $$MediaAlbumRelationsTableFilterComposer,
    $$MediaAlbumRelationsTableOrderingComposer,
    $$MediaAlbumRelationsTableAnnotationComposer,
    $$MediaAlbumRelationsTableCreateCompanionBuilder,
    $$MediaAlbumRelationsTableUpdateCompanionBuilder,
    (
      MediaAlbumRelationEntity,
      BaseReferences<_$AppDatabase, $MediaAlbumRelationsTable,
          MediaAlbumRelationEntity>
    ),
    MediaAlbumRelationEntity,
    PrefetchHooks Function()> {
  $$MediaAlbumRelationsTableTableManager(
      _$AppDatabase db, $MediaAlbumRelationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaAlbumRelationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaAlbumRelationsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaAlbumRelationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> mediaId = const Value.absent(),
            Value<String> albumId = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaAlbumRelationsCompanion(
            mediaId: mediaId,
            albumId: albumId,
            addedAt: addedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String mediaId,
            required String albumId,
            required DateTime addedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaAlbumRelationsCompanion.insert(
            mediaId: mediaId,
            albumId: albumId,
            addedAt: addedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MediaAlbumRelationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MediaAlbumRelationsTable,
    MediaAlbumRelationEntity,
    $$MediaAlbumRelationsTableFilterComposer,
    $$MediaAlbumRelationsTableOrderingComposer,
    $$MediaAlbumRelationsTableAnnotationComposer,
    $$MediaAlbumRelationsTableCreateCompanionBuilder,
    $$MediaAlbumRelationsTableUpdateCompanionBuilder,
    (
      MediaAlbumRelationEntity,
      BaseReferences<_$AppDatabase, $MediaAlbumRelationsTable,
          MediaAlbumRelationEntity>
    ),
    MediaAlbumRelationEntity,
    PrefetchHooks Function()>;
typedef $$TagsTableCreateCompanionBuilder = TagsCompanion Function({
  required String id,
  required String name,
  Value<int> usageCount,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$TagsTableUpdateCompanionBuilder = TagsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> usageCount,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get usageCount => $composableBuilder(
      column: $table.usageCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get usageCount => $composableBuilder(
      column: $table.usageCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get usageCount => $composableBuilder(
      column: $table.usageCount, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TagsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TagsTable,
    TagEntity,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (TagEntity, BaseReferences<_$AppDatabase, $TagsTable, TagEntity>),
    TagEntity,
    PrefetchHooks Function()> {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> usageCount = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TagsCompanion(
            id: id,
            name: name,
            usageCount: usageCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<int> usageCount = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TagsCompanion.insert(
            id: id,
            name: name,
            usageCount: usageCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TagsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TagsTable,
    TagEntity,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (TagEntity, BaseReferences<_$AppDatabase, $TagsTable, TagEntity>),
    TagEntity,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MediaItemsTableTableManager get mediaItems =>
      $$MediaItemsTableTableManager(_db, _db.mediaItems);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db, _db.albums);
  $$MediaAlbumRelationsTableTableManager get mediaAlbumRelations =>
      $$MediaAlbumRelationsTableTableManager(_db, _db.mediaAlbumRelations);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
}
