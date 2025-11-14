import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  static const String _debugModeKey = 'debug_mode_enabled';
  
  final List<LogEntry> _logs = [];
  bool _debugEnabled = true; // 默认启用日志
  File? _logFile;
  Directory? _logsDir;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get debugEnabled => _debugEnabled;

  // 初始化日志服务
  Future<void> initialize() async {
    try {
      print('[SERVER-LOGGER] ========== 开始初始化服务器日志服务 ==========');
      
      // 默认启用日志（开发阶段）
      final prefs = await SharedPreferences.getInstance();
      _debugEnabled = prefs.getBool(_debugModeKey) ?? true; // 默认true
      
      print('[SERVER-LOGGER] 调试模式: $_debugEnabled');
      
      if (_debugEnabled) {
        await _initLogFile();
      } else {
        print('[SERVER-LOGGER] 调试模式已禁用，仅输出到控制台');
      }
    } catch (e, stackTrace) {
      print('[SERVER-LOGGER] ✗ 初始化日志服务失败: $e');
      print('[SERVER-LOGGER] ✗ 堆栈: $stackTrace');
      // 即使初始化失败，也继续运行
    }
  }

  // 设置调试模式
  Future<void> setDebugMode(bool enabled) async {
    _debugEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugModeKey, enabled);
    
    if (enabled) {
      await _initLogFile();
    } else {
      _logFile = null;
    }
  }

  // 初始化日志文件（每次启动都创建新文件）
  Future<void> _initLogFile() async {
    try {
      print('[SERVER-LOGGER] 开始初始化日志文件...');
      
      // Android: 使用应用自己的目录 (/data/data/com.example.remote_cam_server/app_flutter/)
      // Mac/iOS: 使用应用沙盒目录
      final Directory appDir = await getApplicationSupportDirectory();
      print('[SERVER-LOGGER] Application Support目录: ${appDir.path}');
      
      // 创建日志目录
      final String logsDirPath = path.join(appDir.path, 'logs');
      _logsDir = Directory(logsDirPath);
      
      // 确保日志目录存在
      if (!await _logsDir!.exists()) {
        print('[SERVER-LOGGER] 日志目录不存在，正在创建: $logsDirPath');
        await _logsDir!.create(recursive: true);
        print('[SERVER-LOGGER] 日志目录创建成功');
      } else {
        print('[SERVER-LOGGER] 日志目录已存在: $logsDirPath');
      }
      
      // 清理旧日志（在创建新日志之前）
      await _cleanOldLogs();
      
      // 创建新的日志文件（每次启动都创建新文件）
      final String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final String filePath = path.join(logsDirPath, 'debug_$timestamp.log');
      print('[SERVER-LOGGER] 创建新日志文件: $filePath');
      
      _logFile = File(filePath);
      
      // 写入文件头
      await _logFile!.writeAsString('=== Remote Cam Server Debug Log ===\n');
      await _logFile!.writeAsString('Started at: ${DateTime.now()}\n');
      await _logFile!.writeAsString('Platform: ${Platform.operatingSystem}\n');
      await _logFile!.writeAsString('App Support Dir: ${appDir.path}\n');
      await _logFile!.writeAsString('Log File: $filePath\n');
      await _logFile!.writeAsString('=' * 60 + '\n\n');
      
      print('[SERVER-LOGGER] ✓ 日志文件初始化成功: $filePath');
      
      // 写入初始日志
      log('服务器日志系统初始化成功', tag: 'INIT');
      log('日志文件: $filePath', tag: 'INIT');
    } catch (e, stackTrace) {
      print('[SERVER-LOGGER] ✗ 初始化日志文件失败: $e');
      print('[SERVER-LOGGER] ✗ 堆栈: $stackTrace');
      _logFile = null;
    }
  }

  // 记录日志
  void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
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
    
    // 打印到控制台
    print('[${entry.levelString}] ${entry.tag != null ? "[${entry.tag}] " : ""}${entry.message}');
    
    // 写入文件
    if (_debugEnabled && _logFile != null) {
      _writeToFile(entry);
    }
  }

  // HTTP请求日志
  void logHttpRequest(String method, String path, {Map<String, dynamic>? body}) {
    final message = 'HTTP $method $path${body != null ? "\nBody: $body" : ""}';
    log(message, level: LogLevel.request, tag: 'HTTP');
  }

  // HTTP响应日志
  void logHttpResponse(int statusCode, String path, {dynamic body}) {
    final message = 'Response $statusCode for $path${body != null ? "\nBody: $body" : ""}';
    log(message, level: LogLevel.response, tag: 'HTTP');
  }

  // 相机操作日志
  void logCamera(String operation, {String? details}) {
    final message = 'Camera: $operation${details != null ? " - $details" : ""}';
    log(message, level: LogLevel.info, tag: 'CAMERA');
  }

  // 错误日志
  void logError(String message, {Object? error, StackTrace? stackTrace}) {
    final fullMessage = '$message${error != null ? "\nError: $error" : ""}${stackTrace != null ? "\nStack: $stackTrace" : ""}';
    log(fullMessage, level: LogLevel.error, tag: 'ERROR');
  }

  // 写入文件
  Future<void> _writeToFile(LogEntry entry) async {
    try {
      final line = '[${entry.timestamp.toString()}] [${entry.levelString}] ${entry.tag != null ? "[${entry.tag}] " : ""}${entry.message}\n';
      await _logFile!.writeAsString(line, mode: FileMode.append);
    } catch (e) {
      print('[SERVER-LOGGER] 写入日志文件失败: $e');
      // 如果写入失败，尝试重新初始化
      _logFile = null;
    }
  }

  // 获取日志文件路径
  Future<String?> getLogFilePath() async {
    return _logFile?.path;
  }

  // 清除内存中的日志
  void clearLogs() {
    _logs.clear();
  }

  // 获取所有日志文件
  Future<List<File>> getLogFiles() async {
    try {
      if (_logsDir == null) {
        final Directory appDir = await getApplicationSupportDirectory();
        final String logsDirPath = path.join(appDir.path, 'logs');
        _logsDir = Directory(logsDirPath);
      }
      
      if (!await _logsDir!.exists()) {
        return [];
      }
      
      return _logsDir!
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    } catch (e) {
      print('[SERVER-LOGGER] 获取日志文件列表失败: $e');
      return [];
    }
  }

  // 清理旧日志（保留最近10个，单个文件最大10MB，总大小最大50MB）
  Future<void> _cleanOldLogs() async {
    try {
      final files = await getLogFiles();
      if (files.isEmpty) {
        print('[SERVER-LOGGER] 没有旧日志文件需要清理');
        return;
      }
      
      print('[SERVER-LOGGER] 找到 ${files.length} 个日志文件，开始清理...');
      
      // 按修改时间排序（最新的在前）
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      
      int totalSize = 0;
      int keptCount = 0;
      int deletedCount = 0;
      
      for (var file in files) {
        final size = await file.length();
        
        // 如果文件超过10MB，删除
        if (size > 10 * 1024 * 1024) {
          print('[SERVER-LOGGER] 删除超大日志文件: ${file.path} (${(size / 1024 / 1024).toStringAsFixed(2)}MB)');
          await file.delete();
          deletedCount++;
          continue;
        }
        
        // 如果总大小超过50MB，删除
        if (totalSize + size > 50 * 1024 * 1024) {
          print('[SERVER-LOGGER] 删除日志文件（总大小限制）: ${file.path}');
          await file.delete();
          deletedCount++;
          continue;
        }
        
        // 如果保留的文件超过10个，删除
        if (keptCount >= 10) {
          print('[SERVER-LOGGER] 删除旧日志文件: ${file.path}');
          await file.delete();
          deletedCount++;
          continue;
        }
        
        totalSize += size;
        keptCount++;
      }
      
      print('[SERVER-LOGGER] 日志清理完成: 保留 $keptCount 个，删除 $deletedCount 个');
    } catch (e) {
      print('[SERVER-LOGGER] 清理旧日志失败: $e');
    }
  }

  // 清理旧日志（公开方法，供UI调用）
  Future<void> cleanOldLogs() async {
    await _cleanOldLogs();
  }

  // 清理所有日志（公开方法）
  Future<void> cleanAllLogs() async {
    try {
      if (_logsDir == null) {
        final Directory appDir = await getApplicationSupportDirectory();
        final String logsDirPath = path.join(appDir.path, 'logs');
        _logsDir = Directory(logsDirPath);
      }
      
      if (!await _logsDir!.exists()) {
        print('[SERVER-LOGGER] 日志目录不存在，无需清理');
        return;
      }
      
      final files = await getLogFiles();
      print('[SERVER-LOGGER] 清理所有日志文件，共 ${files.length} 个');
      
      for (var file in files) {
        await file.delete();
      }
      
      print('[SERVER-LOGGER] 所有日志文件已清理');
    } catch (e) {
      print('[SERVER-LOGGER] 清理所有日志失败: $e');
      rethrow;
    }
  }
}

enum LogLevel {
  debug,
  info,
  request,
  response,
  warning,
  error,
}

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

  String get levelString {
    switch (level) {
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

  String get timeString {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }
}
