/// 数据源类型
enum SourceType {
  /// 本地导入（从本地文件系统导入）
  localImport,

  /// 手机相机（远程手机服务端）
  phoneCamera,

  /// IP 摄像头（RTSP/ONVIF）
  ipCamera,

  /// 任务服务器
  taskServer,
}

/// 数据源状态
enum SourceStatus {
  /// 未连接
  disconnected,

  /// 连接中
  connecting,

  /// 已连接
  connected,

  /// 连接错误
  error,
}

/// 数据源错误
class SourceError {
  final String code;
  final String message;
  final String? details;
  final dynamic originalError;

  const SourceError({
    required this.code,
    required this.message,
    this.details,
    this.originalError,
  });

  factory SourceError.fromException(dynamic e) {
    return SourceError(
      code: 'exception',
      message: e.toString(),
      originalError: e,
    );
  }

  factory SourceError.connectionFailed(String message) {
    return SourceError(
      code: 'connection_failed',
      message: message,
    );
  }

  factory SourceError.timeout() {
    return const SourceError(
      code: 'timeout',
      message: '连接超时',
    );
  }

  factory SourceError.versionIncompatible(String message) {
    return SourceError(
      code: 'version_incompatible',
      message: message,
    );
  }

  @override
  String toString() => 'SourceError($code): $message';
}

/// 数据源配置基类
abstract class SourceConfig {
  /// 配置唯一标识
  String get id;

  /// 数据源名称
  String get name;

  /// 数据源类型
  SourceType get type;

  /// 转换为 JSON
  Map<String, dynamic> toJson();
}
