import 'dart:async';

/// 远程文件信息
class RemoteFileInfo {
  final String path;
  final String name;
  final int size;
  final DateTime createdTime;
  final DateTime? modifiedTime;
  final bool isVideo;
  final bool isStarred;

  const RemoteFileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.createdTime,
    this.modifiedTime,
    required this.isVideo,
    this.isStarred = false,
  });
}

/// 文件列表结果
class FileListResult {
  final bool success;
  final List<RemoteFileInfo> files;
  final int total;
  final int page;
  final bool hasMore;
  final String? error;

  const FileListResult({
    required this.success,
    this.files = const [],
    this.total = 0,
    this.page = 1,
    this.hasMore = false,
    this.error,
  });

  factory FileListResult.success({
    required List<RemoteFileInfo> files,
    int total = 0,
    int page = 1,
    bool hasMore = false,
  }) {
    return FileListResult(
      success: true,
      files: files,
      total: total,
      page: page,
      hasMore: hasMore,
    );
  }

  factory FileListResult.failure(String error) {
    return FileListResult(
      success: false,
      error: error,
    );
  }
}

/// 文件源能力接口
///
/// 实现此接口的数据源可以提供远程文件列表和下载
abstract class FileSourceCapability {
  /// 获取文件列表
  ///
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页大小
  /// [since] 增量获取：只获取该时间之后的文件
  Future<FileListResult> getFileList({
    int? page,
    int? pageSize,
    DateTime? since,
  });

  /// 获取文件下载 URL
  String getFileDownloadUrl(String remotePath);

  /// 获取缩略图 URL
  Future<String> getThumbnailUrl(String remotePath, {bool isVideo = false});

  /// 删除远程文件
  Future<bool> deleteRemoteFile(String remotePath);

  /// 切换文件星标状态
  Future<bool> toggleStarred(String remotePath);

  /// 新文件通知流（用于监听服务器推送的新文件）
  Stream<List<RemoteFileInfo>>? get newFilesStream;
}
