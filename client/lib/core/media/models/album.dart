/// 相册类型
enum AlbumType {
  normal,     // 普通相册（用户创建）
  smart,      // 智能相册（自动分类）
  source,     // 数据源相册（按来源分类）
  starred,    // 星标相册（系统内置）
  all,        // 全部媒体（系统内置）
}

extension AlbumTypeExtension on AlbumType {
  String get displayName {
    switch (this) {
      case AlbumType.normal:
        return '相册';
      case AlbumType.smart:
        return '智能相册';
      case AlbumType.source:
        return '来源';
      case AlbumType.starred:
        return '星标';
      case AlbumType.all:
        return '全部';
    }
  }

  String get dbValue => name;

  static AlbumType fromDbValue(String value) {
    return AlbumType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AlbumType.normal,
    );
  }
}

/// 相册模型
class Album {
  final String id;
  final String name;
  final String? description;
  final AlbumType type;
  final String? coverMediaId;       // 封面媒体ID
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final int mediaCount;             // 媒体数量（缓存值）
  final String? sourceId;           // 关联的数据源ID（仅 source 类型）
  final Map<String, dynamic>? smartCriteria; // 智能相册筛选条件

  const Album({
    required this.id,
    required this.name,
    this.description,
    this.type = AlbumType.normal,
    this.coverMediaId,
    required this.createdAt,
    this.modifiedAt,
    this.mediaCount = 0,
    this.sourceId,
    this.smartCriteria,
  });

  /// 是否为系统相册（不可删除）
  bool get isSystem => type == AlbumType.starred || type == AlbumType.all;

  /// 是否为智能相册（自动更新）
  bool get isSmart => type == AlbumType.smart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type.dbValue,
        'coverMediaId': coverMediaId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt?.toIso8601String(),
        'mediaCount': mediaCount,
        'sourceId': sourceId,
        'smartCriteria': smartCriteria,
      };

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      type: AlbumTypeExtension.fromDbValue(json['type'] as String? ?? 'normal'),
      coverMediaId: json['coverMediaId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : null,
      mediaCount: json['mediaCount'] as int? ?? 0,
      sourceId: json['sourceId'] as String?,
      smartCriteria: json['smartCriteria'] as Map<String, dynamic>?,
    );
  }

  Album copyWith({
    String? id,
    String? name,
    String? description,
    AlbumType? type,
    String? coverMediaId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? mediaCount,
    String? sourceId,
    Map<String, dynamic>? smartCriteria,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      coverMediaId: coverMediaId ?? this.coverMediaId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      mediaCount: mediaCount ?? this.mediaCount,
      sourceId: sourceId ?? this.sourceId,
      smartCriteria: smartCriteria ?? this.smartCriteria,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Album(id: $id, name: $name, type: $type)';
}
