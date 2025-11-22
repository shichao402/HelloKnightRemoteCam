import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared/shared.dart';

class ClientLoggerService {
  static final ClientLoggerService _instance = ClientLoggerService._internal();
  factory ClientLoggerService() => _instance;
  ClientLoggerService._internal();

  static const String _debugModeKey = 'client_debug_mode_enabled';

  bool _initialized = false;
  bool _debugEnabled = false; // 默认关闭日志以提高效率

  // 获取日志目录路径的回调函数（用于LogFileManager和文件头）
  Future<String> _getLogsDirectoryPath() async {
    // 检查应用是否为沙盒应用
    final Directory appSupportDir = await getApplicationSupportDirectory();

    String logsDirPath;

    // 判断是否为沙盒应用：沙盒应用的Application Support路径包含Containers
    if (appSupportDir.path.contains('/Containers/')) {
      // 沙盒应用：日志存储在 ~/Library/Containers/<Bundle ID>/Data/Library/Logs/
      final String appSupportPath = appSupportDir.path;
      // 从 Application Support 构建到 Library/Logs
      final String libraryPath = appSupportPath.replaceAll(
          '/Application Support/com.example.remoteCamClient', '');
      logsDirPath = path.join(libraryPath, 'Logs');
    } else {
      // 非沙盒应用：日志存储在 ~/Library/Logs/<应用名称>/
      final String homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) {
        throw Exception('无法获取用户主目录');
      }
      // 使用应用名称作为日志目录名
      logsDirPath = path.join(homeDir, 'Library', 'Logs', 'HelloKnightRCC');
    }

    return logsDirPath;
  }

  // 使用shared包的LogFileManager
  late final LogFileManager _logFileManager = LogFileManager(
    getLogsDirectoryPath: _getLogsDirectoryPath,
    logFilePrefix: 'client_debug_',
    logHeaderTitle: '=== Remote Cam Client Debug Log ===',
    onLog: (message, {tag}) => log(message, tag: tag),
    onLogError: (message, {error, stackTrace}) =>
        logError(message, error: error, stackTrace: stackTrace),
  );

  bool get debugEnabled => _debugEnabled;

  // 初始化日志服务
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      // 从SharedPreferences读取调试模式设置
      final prefs = await SharedPreferences.getInstance();
      _debugEnabled = prefs.getBool(_debugModeKey) ?? false; // 默认false

      if (!_debugEnabled) {
        _initialized = true;
        return;
      }

      // 初始化日志文件（使用shared包的LogFileManager）
      await _initLogFile();

      _initialized = true;

      // 写入初始日志
      log('客户端日志系统初始化成功', tag: 'INIT');
      final logFilePath = _logFileManager.logFilePath;
      if (logFilePath != null) {
        log('日志文件: $logFilePath', tag: 'INIT');
      }
    } catch (e, stackTrace) {
      // 调试模式关闭时不输出错误
      if (_debugEnabled) {
        print('[LOGGER] ✗ 初始化日志文件失败: $e');
        print('[LOGGER] ✗ 堆栈: $stackTrace');
      }
      _initialized = false;
      rethrow; // 重新抛出异常，让调用者知道初始化失败
    }
  }

  // 设置调试模式
  Future<void> setDebugMode(bool enabled) async {
    _debugEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugModeKey, enabled);

    if (enabled) {
      // 如果启用调试模式，初始化日志文件
      if (!_initialized) {
        await initialize();
      } else {
        // 如果已经初始化但之前禁用了，重新初始化日志文件
        await _initLogFile();
      }
    }
  }

  // 初始化日志文件（内部方法，使用shared包的LogFileManager）
  Future<void> _initLogFile() async {
    try {
      // 获取日志目录路径（用于文件头）
      final logsDirPath = await _getLogsDirectoryPath();
      final Directory appSupportDir = await getApplicationSupportDirectory();
      final additionalHeaderInfo =
          'App Support Dir: ${appSupportDir.path}\nLog Dir: $logsDirPath';

      // 使用shared包的LogFileManager初始化日志文件
      await _logFileManager.initializeLogFile(
        additionalHeaderInfo: additionalHeaderInfo,
      );
    } catch (e, stackTrace) {
      // 调试模式关闭时不输出错误
      if (_debugEnabled) {
        print('[LOGGER] ✗ 初始化日志文件失败: $e');
        print('[LOGGER] ✗ 堆栈: $stackTrace');
      }
    }
  }

  // 记录日志
  void log(String message, {String? tag}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }

    final timestamp = DateTime.now().toString();
    final tagStr = tag != null ? '[$tag] ' : '';
    final line = '[$timestamp] $tagStr$message';

    // 打印到控制台（仅在调试模式启用时）
    print('$tagStr$message');

    // 写入文件（使用shared包的LogFileManager，异步执行不阻塞）
    if (_initialized) {
      _logFileManager.writeLogLine(line).catchError((e) {
        // 调试模式关闭时不输出错误
        if (_debugEnabled) {
          print('[LOGGER] 写入日志失败: $e');
        }
      });
    }
  }

  // API调用日志（增强版，记录更多详情）
  void logApiCall(String method, String endpoint,
      {Map<String, dynamic>? params,
      Map<String, String>? headers,
      String? body}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final paramsStr = params != null ? '\n参数: $params' : '';
    final headersStr =
        headers != null && headers.isNotEmpty ? '\n请求头: $headers' : '';
    final bodyStr = body != null ? '\n请求体: $body' : '';
    log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'API');
    log('→ API调用: $method $endpoint$paramsStr$headersStr$bodyStr', tag: 'API');
  }

  // API响应日志（增强版，记录更多详情）
  void logApiResponse(String endpoint, int statusCode,
      {dynamic body, String? error}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final bodyStr = body != null ? '\n响应体: $body' : '';
    final errorStr = error != null ? '\n错误: $error' : '';
    final statusIcon = statusCode >= 200 && statusCode < 300 ? '✓' : '✗';
    log('$statusIcon API响应: $endpoint -> HTTP $statusCode$bodyStr$errorStr',
        tag: 'API');
    log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'API');
  }

  // 指令记录（记录所有发送到服务端的指令）
  void logCommand(String command,
      {Map<String, dynamic>? params, String? details}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final paramsStr = params != null ? '\n参数: $params' : '';
    final detailsStr = details != null ? '\n详情: $details' : '';
    log('📤 发送指令: $command$paramsStr$detailsStr', tag: 'COMMAND');
  }

  // 指令响应记录
  void logCommandResponse(String command,
      {bool success = true, dynamic result, String? error}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    final icon = success ? '✓' : '✗';
    final resultStr = result != null ? '\n结果: $result' : '';
    final errorStr = error != null ? '\n错误: $error' : '';
    log('$icon 指令响应: $command -> ${success ? "成功" : "失败"}$resultStr$errorStr',
        tag: 'COMMAND');
  }

  // 下载日志
  void logDownload(String action, {String? details}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    log('下载: $action${details != null ? " - $details" : ""}', tag: 'DOWNLOAD');
  }

  // 错误日志
  void logError(String message, {Object? error, StackTrace? stackTrace}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    log('错误: $message', tag: 'ERROR');
    if (error != null) {
      log('异常: $error', tag: 'ERROR');
    }
    if (stackTrace != null) {
      log('堆栈: $stackTrace', tag: 'ERROR');
    }
  }

  // 连接日志
  void logConnection(String action, {String? details}) {
    // 调试模式关闭时不输出任何日志
    if (!_debugEnabled) {
      return;
    }
    log('连接: $action${details != null ? " - $details" : ""}',
        tag: 'CONNECTION');
  }

  // 获取日志文件路径（使用shared包的LogFileManager）
  String? get logFilePath => _logFileManager.logFilePath;

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
