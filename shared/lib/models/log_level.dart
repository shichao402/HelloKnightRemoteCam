/// 日志级别枚举
/// 客户端和服务端共享
enum LogLevel {
  debug,
  info,
  request,
  response,
  warning,
  error,
}

/// 日志级别扩展方法
extension LogLevelExtension on LogLevel {
  /// 获取日志级别的字符串表示
  String get levelString {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.request:
        return 'REQ';
      case LogLevel.response:
        return 'RES';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}

