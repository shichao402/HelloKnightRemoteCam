import 'log_level.dart';

/// 日志条目
/// 客户端和服务端共享
class LogEntry {
  final String message;
  final LogLevel level;
  final String? tag;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    this.tag,
    required this.timestamp,
  });

  /// 获取时间字符串（HH:mm:ss格式）
  String get timeString {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  /// 格式化为日志行
  String toLogLine() {
    return '[${timestamp.toString()}] [${level.levelString}] ${tag != null ? "[$tag] " : ""}$message';
  }
}

