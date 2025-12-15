import 'media_type.dart';
import 'media_metadata.dart';
import '../../../models/file_info.dart';

/// 同步状态
enum SyncStatus {
  local,      // 仅本地
  synced,     // 已同步
  pending,    // 等待同步
  failed,     // 同步失败
}

/// 媒体项模型 - 扩展自 FileInfo 概念
class MediaItem {
  final String id;                  // 本地唯一ID
  final String name;                // 文件名
  final String localPath;           // 本地存储路径
  final MediaType type;             // 媒体类型
  final int size;                   // 文件大小（字节）
  final DateTime createdAt;         // 创建时间
  final DateTime? modifiedAt;       // 修改时间
  final String? thumbnailPath;      // 缩略图路径
  final MediaMetadata? metadata;    // 元数据
  final String? sourceId;           // 来源数据源ID
  final String? sourceRef;          // 来源引用（远程路径等）
  final bool isStarred;             // 是否星标
  final List<String> tags;          // 标签列表
  final String? albumId;            // 所属相册ID
  final SyncStatus syncStatus;      // 同步状态

  const MediaItem({
    required this.id,
    required this.name,
    required this.localPath,
    required this.type,
    required this.size,
    required this.createdAt,
    this.modifiedAt,
    this.thumbnailPath,
    this.metadata,
    this.sourceId,
    this.sourceRef,
    this.isStarred = false,
    this.tags = const [],
    this.albumId,
    this.syncStatus = SyncStatus.local,
  });

  // === 复用 FileInfo 的格式化方法 ===
  
  /// 格式化文件大小
  String get formattedSize {
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

  /// 判断是否为视频文件
  bool get isVideo => type == MediaType.video;

  /// 判断是否为图片文件
  bool get isImage => type == MediaType.photo;

  /// 文件扩展名
  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  // === 兼容性：从 FileInfo 转换 ===
  
  factory MediaItem.fromFileInfo(
    FileInfo fileInfo, {
    required String id,
    String? sourceId,
    String? thumbnailPath,
  }) {
    final type = fileInfo.isVideo ? MediaType.video : MediaType.photo;
    return MediaItem(
      id: id,
      name: fileInfo.name,
      localPath: fileInfo.path,
      type: type,
      size: fileInfo.size,
      createdAt: fileInfo.createdTime,
      modifiedAt: fileInfo.modifiedTime,
      thumbnailPath: thumbnailPath,
      sourceId: sourceId,
      sourceRef: fileInfo.path,
      isStarred: fileInfo.isStarred,
    );
  }

  /// 转换为 FileInfo（向后兼容）
  FileInfo toFileInfo() {
    return FileInfo(
      name: name,
      path: localPath,
      size: size,
      createdTime: createdAt,
      modifiedTime: modifiedAt ?? createdAt,
      isStarred: isStarred,
    );
  }

  // === JSON 序列化 ===

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'localPath': localPath,
        'type': type.dbValue,
        'size': size,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt?.toIso8601String(),
        'thumbnailPath': thumbnailPath,
        'metadata': metadata?.toJson(),
        'sourceId': sourceId,
        'sourceRef': sourceRef,
        'isStarred': isStarred,
        'tags': tags,
        'albumId': albumId,
        'syncStatus': syncStatus.name,
      };

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      name: json['name'] as String,
      localPath: json['localPath'] as String,
      type: MediaTypeExtension.fromDbValue(json['type'] as String),
      size: json['size'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : null,
      thumbnailPath: json['thumbnailPath'] as String?,
      metadata: json['metadata'] != null
          ? MediaMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
      sourceId: json['sourceId'] as String?,
      sourceRef: json['sourceRef'] as String?,
      isStarred: json['isStarred'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      albumId: json['albumId'] as String?,
      syncStatus: SyncStatus.values.firstWhere(
        (e) => e.name == json['syncStatus'],
        orElse: () => SyncStatus.local,
      ),
    );
  }

  // === copyWith ===

  MediaItem copyWith({
    String? id,
    String? name,
    String? localPath,
    MediaType? type,
    int? size,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? thumbnailPath,
    MediaMetadata? metadata,
    String? sourceId,
    String? sourceRef,
    bool? isStarred,
    List<String>? tags,
    String? albumId,
    SyncStatus? syncStatus,
  }) {
    return MediaItem(
      id: id ?? this.id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      type: type ?? this.type,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      metadata: metadata ?? this.metadata,
      sourceId: sourceId ?? this.sourceId,
      sourceRef: sourceRef ?? this.sourceRef,
      isStarred: isStarred ?? this.isStarred,
      tags: tags ?? this.tags,
      albumId: albumId ?? this.albumId,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MediaItem(id: $id, name: $name, type: $type)';
}
