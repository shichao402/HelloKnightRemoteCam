/// 日志回调函数类型定义
/// 用于shared包中的服务类，避免依赖特定的logger实现

/// 普通日志回调
typedef LogCallback = void Function(String message, {String? tag});

/// 错误日志回调
typedef LogErrorCallback = void Function(String message, {Object? error, StackTrace? stackTrace});

