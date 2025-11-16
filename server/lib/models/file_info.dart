// 文件信息
class FileInfo {
  final String name;          // 文件名
  final String path;          // 完整路径
  final int size;             // 文件大小（字节）
  final DateTime createdTime; // 创建时间
  final DateTime modifiedTime; // 修改时间

  FileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.createdTime,
    required this.modifiedTime,
  });

  // 格式化文件大小
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

  // JSON 序列化
  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'size': size,
        'createdTime': createdTime.toIso8601String(),
        'modifiedTime': modifiedTime.toIso8601String(),
      };

  // JSON 反序列化
  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
      createdTime: json['createdTime'] != null
          ? DateTime.parse(json['createdTime'] as String)
          : DateTime.parse(json['modifiedTime'] as String), // 兼容旧数据
      modifiedTime: DateTime.parse(json['modifiedTime'] as String),
    );
  }
}

