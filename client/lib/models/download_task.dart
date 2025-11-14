// 下载任务状态
enum DownloadStatus {
  pending,     // 等待中
  downloading, // 下载中
  paused,      // 已暂停
  completed,   // 已完成
  failed,      // 失败
}

// 下载任务
class DownloadTask {
  final String id;              // 任务ID
  final String remoteFilePath;  // 远程文件路径
  final String localFilePath;   // 本地保存路径
  final String fileName;        // 文件名
  int totalBytes;               // 总字节数（可变，因为可能在下载过程中获取）
  int downloadedBytes;          // 已下载字节数
  DownloadStatus status;        // 状态
  int retryCount;               // 重试次数
  DateTime? startTime;          // 开始时间
  DateTime? endTime;            // 结束时间
  String? errorMessage;         // 错误信息

  DownloadTask({
    required this.id,
    required this.remoteFilePath,
    required this.localFilePath,
    required this.fileName,
    required this.totalBytes,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.pending,
    this.retryCount = 0,
    this.startTime,
    this.endTime,
    this.errorMessage,
  });

  // 计算下载进度 (0.0 - 1.0)
  double get progress {
    if (totalBytes == 0) return 0.0;
    return downloadedBytes / totalBytes;
  }

  // 计算下载进度百分比
  int get progressPercent {
    return (progress * 100).round();
  }

  // 是否可以重试
  bool get canRetry {
    return status == DownloadStatus.failed && retryCount < 3;
  }

  // 是否正在进行
  bool get isActive {
    return status == DownloadStatus.downloading;
  }

  // 是否完成
  bool get isCompleted {
    return status == DownloadStatus.completed;
  }

  // JSON 序列化
  Map<String, dynamic> toJson() => {
        'id': id,
        'remoteFilePath': remoteFilePath,
        'localFilePath': localFilePath,
        'fileName': fileName,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'status': status.toString(),
        'retryCount': retryCount,
        'startTime': startTime?.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'errorMessage': errorMessage,
      };

  // JSON 反序列化
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      remoteFilePath: json['remoteFilePath'] as String,
      localFilePath: json['localFilePath'] as String,
      fileName: json['fileName'] as String,
      totalBytes: json['totalBytes'] as int,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      status: _parseStatus(json['status'] as String?),
      retryCount: json['retryCount'] as int? ?? 0,
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  static DownloadStatus _parseStatus(String? status) {
    switch (status) {
      case 'DownloadStatus.pending':
        return DownloadStatus.pending;
      case 'DownloadStatus.downloading':
        return DownloadStatus.downloading;
      case 'DownloadStatus.paused':
        return DownloadStatus.paused;
      case 'DownloadStatus.completed':
        return DownloadStatus.completed;
      case 'DownloadStatus.failed':
        return DownloadStatus.failed;
      default:
        return DownloadStatus.pending;
    }
  }

  // 复制并修改
  DownloadTask copyWith({
    String? id,
    String? remoteFilePath,
    String? localFilePath,
    String? fileName,
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    int? retryCount,
    DateTime? startTime,
    DateTime? endTime,
    String? errorMessage,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      remoteFilePath: remoteFilePath ?? this.remoteFilePath,
      localFilePath: localFilePath ?? this.localFilePath,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

