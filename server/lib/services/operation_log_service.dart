import 'dart:collection';

/// 操作日志服务 - 记录关键操作
class OperationLogService {
  static final OperationLogService _instance = OperationLogService._internal();
  factory OperationLogService() => _instance;
  OperationLogService._internal();

  // 使用固定大小的队列，最多保存10条记录
  final Queue<OperationLog> _logs = Queue<OperationLog>();
  static const int maxLogs = 10;

  /// 添加操作日志
  void addLog({
    required OperationType type,
    required String clientIp,
    String? fileName,
  }) {
    final log = OperationLog(
      type: type,
      clientIp: clientIp,
      fileName: fileName,
      timestamp: DateTime.now(),
    );

    _logs.addFirst(log); // 新日志添加到前面

    // 保持最多10条记录
    while (_logs.length > maxLogs) {
      _logs.removeLast();
    }
  }

  /// 获取所有日志（最新的在前）
  List<OperationLog> getLogs() {
    return _logs.toList();
  }

  /// 清空日志
  void clear() {
    _logs.clear();
  }
}

/// 操作类型
enum OperationType {
  takePicture,    // 拍照
  startRecording, // 开始录像
  stopRecording,  // 停止录像
  downloadStart,  // 开始下载
  downloadComplete, // 下载完成
  connect,        // 连接
  disconnect,     // 断开连接
}

/// 操作日志
class OperationLog {
  final OperationType type;
  final String clientIp;
  final String? fileName;
  final DateTime timestamp;

  OperationLog({
    required this.type,
    required this.clientIp,
    this.fileName,
    required this.timestamp,
  });

  String get typeText {
    switch (type) {
      case OperationType.takePicture:
        return '拍照';
      case OperationType.startRecording:
        return '开始录像';
      case OperationType.stopRecording:
        return '停止录像';
      case OperationType.downloadStart:
        return '开始下载';
      case OperationType.downloadComplete:
        return '下载完成';
      case OperationType.connect:
        return '连接';
      case OperationType.disconnect:
        return '断开连接';
    }
  }

  String get displayText {
    if (fileName != null) {
      return '$typeText: $fileName';
    }
    return typeText;
  }
}

