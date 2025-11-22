import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared/shared.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  static const String _debugModeKey = 'debug_mode_enabled';

  final List<LogEntry> _logs = [];
  bool _debugEnabled = false; // 默认关闭日志以提高效率

  // 使用shared包的LogFileManager
  late final LogFileManager _logFileManager = LogFileManager(
    getLogsDirectoryPath: () async {
      final Directory appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'logs');
    },
    logFilePrefix: 'debug_',
    logHeaderTitle: '=== Remote Cam Server Debug Log ===',
    onLog: (message, {tag}) => log(message, tag: tag),
    onLogError: (message, {error, stackTrace}) =>
        logError(message, error: error, stackTrace: stackTrace),
  );

  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get debugEnabled => _debugEnabled;

  // 初始化日志服务
  Future<void> initialize() async {
    try {
      // 默认关闭日志（生产环境）
      final prefs = await SharedPreferences.getInstance();
      _debugEnabled = prefs.getBool(_debugModeKey) ?? false; // 默认false

      if (_debugEnabled) {
        await _initLogFile();
      }
      // 调试模式关闭时不输出任何日志
    } catch (e, stackTrace) {
      // 即使初始化失败，也继续运行（调试模式关闭时不输出错误）
      if (_debugEnabled) {
        print('[SERVER-LOGGER] ✗ 初始化日志服务失败: $e');
        print('[SERVER-LOGGER] ✗ 堆栈: $stackTrace');
      }
    }
  }

  // 设置调试模式
  Future<void> setDebugMode(bool enabled) async {
    _debugEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugModeKey, enabled);

    if (enabled) {
      await _initLogFile();
    }
  }

  // 初始化日志文件（每次启动都创建新文件）
  Future<void> _initLogFile() async {
    try {
      // 使用shared包的LogFileManager初始化日志文件
      final Directory appDir = await getApplicationSupportDirectory();
      final additionalHeaderInfo = 'App Support Dir: ${appDir.path}';

      final logFile = await _logFileManager.initializeLogFile(
        additionalHeaderInfo: additionalHeaderInfo,
      );

      if (logFile != null) {
        // 写入初始日志
        log('服务器日志系统初始化成功', tag: 'INIT');
        log('日志文件: ${logFile.path}', tag: 'INIT');
      }
    } catch (e, stackTrace) {
      // 调试模式关闭时不输出错误
      if (_debugEnabled) {
        print('[SERVER-LOGGER] ✗ 初始化日志文件失败: $e');
        print('[SERVER-LOGGER] ✗ 堆栈: $stackTrace');
      }
    }
  }

  // 记录日志
  void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    // 调试模式关闭时不输出任何日志，也不添加到内存
    if (!_debugEnabled) {
      return;
    }

    final entry = LogEntry(
      message: message,
      level: level,
      tag: tag,
      timestamp: DateTime.now(),
    );

    _logs.add(entry);

    // 只保留最近500条日志（内存中）
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }

    // 打印到控制台（仅在调试模式启用时）
    print(
        '[${entry.level.levelString}] ${entry.tag != null ? "[${entry.tag}] " : ""}${entry.message}');

    // 写入文件（使用shared包的LogFileManager）
    _writeToFile(entry);
  }

  // HTTP请求日志
  void logHttpRequest(String method, String path,
      {Map<String, dynamic>? body}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final message = 'HTTP $method $path${body != null ? "\nBody: $body" : ""}';
    log(message, level: LogLevel.request, tag: 'HTTP');
  }

  // HTTP响应日志
  void logHttpResponse(int statusCode, String path, {dynamic body}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final message =
        'Response $statusCode for $path${body != null ? "\nBody: $body" : ""}';
    log(message, level: LogLevel.response, tag: 'HTTP');
  }

  // 相机操作日志
  void logCamera(String operation, {String? details}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final message = 'Camera: $operation${details != null ? " - $details" : ""}';
    log(message, level: LogLevel.info, tag: 'CAMERA');
  }

  // 错误日志
  void logError(String message, {Object? error, StackTrace? stackTrace}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final fullMessage =
        '$message${error != null ? "\nError: $error" : ""}${stackTrace != null ? "\nStack: $stackTrace" : ""}';
    log(fullMessage, level: LogLevel.error, tag: 'ERROR');
  }

  // 写入文件（使用shared包的LogFileManager）
  Future<void> _writeToFile(LogEntry entry) async {
    final line = entry.toLogLine();
    await _logFileManager.writeLogLine(line);
  }

  // 获取日志文件路径（使用shared包的LogFileManager）
  Future<String?> getLogFilePath() async {
    return _logFileManager.logFilePath;
  }

  // 清除内存中的日志
  void clearLogs() {
    _logs.clear();
  }

  // 获取所有日志文件（使用shared包的LogFileManager）
  Future<List<File>> getLogFiles() async {
    return await _logFileManager.getLogFiles();
  }

  // 清理旧日志（公开方法，供UI调用，使用shared包的LogFileManager）
  Future<void> cleanOldLogs() async {
    await _logFileManager.cleanOldLogs();
  }

  // 清理所有日志（公开方法，使用shared包的LogFileManager）
  Future<void> cleanAllLogs() async {
    await _logFileManager.cleanAllLogs();
  }
}

// LogLevel 和 LogEntry 已移至 shared 包
