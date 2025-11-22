import 'dart:io';
import 'package:path/path.dart' as path;
import '../types/log_callbacks.dart';

/// 日志文件管理器
/// 负责日志文件的创建、写入、清理等操作
/// 客户端和服务端共享
class LogFileManager {
  /// 日志回调（可选）
  LogCallback? onLog;
  LogErrorCallback? onLogError;

  /// 日志目录路径提供者（必须）
  final Future<String> Function() getLogsDirectoryPath;

  /// 日志文件前缀（例如：'client_debug_' 或 'debug_'）
  final String logFilePrefix;

  /// 日志文件头标题（例如：'=== Remote Cam Client Debug Log ==='）
  final String logHeaderTitle;

  /// 当前日志文件
  File? _logFile;

  /// 日志目录
  Directory? _logsDir;

  /// 最大保留文件数
  final int maxFiles;

  /// 单个文件最大大小（字节）
  final int maxFileSize;

  /// 总大小限制（字节）
  final int maxTotalSize;

  LogFileManager({
    required this.getLogsDirectoryPath,
    required this.logFilePrefix,
    required this.logHeaderTitle,
    this.onLog,
    this.onLogError,
    this.maxFiles = 10,
    this.maxFileSize = 10 * 1024 * 1024, // 10MB
    this.maxTotalSize = 50 * 1024 * 1024, // 50MB
  });

  /// 初始化日志文件
  Future<File?> initializeLogFile({
    String? additionalHeaderInfo,
  }) async {
    try {
      // 获取日志目录路径
      final logsDirPath = await getLogsDirectoryPath();
      _logsDir = Directory(logsDirPath);

      // 确保日志目录存在
      if (!await _logsDir!.exists()) {
        await _logsDir!.create(recursive: true);
      }

      // 清理旧日志（在创建新日志之前）
      await _cleanOldLogs();

      // 创建新的日志文件（每次启动都创建新文件）
      final String timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-');
      final String filePath =
          path.join(logsDirPath, '${logFilePrefix}$timestamp.log');

      _logFile = File(filePath);

      // 写入文件头
      await _writeHeader(additionalHeaderInfo: additionalHeaderInfo);

      return _logFile;
    } catch (e, stackTrace) {
      onLogError?.call('初始化日志文件失败', error: e, stackTrace: stackTrace);
      _logFile = null;
      return null;
    }
  }

  /// 写入文件头
  Future<void> _writeHeader({String? additionalHeaderInfo}) async {
    if (_logFile == null) return;

    final header = StringBuffer();
    header.writeln('$logHeaderTitle');
    header.writeln('Started at: ${DateTime.now()}');
    header.writeln('Platform: ${Platform.operatingSystem}');

    if (additionalHeaderInfo != null) {
      header.writeln(additionalHeaderInfo);
    }

    header.writeln('Log File: ${_logFile!.path}');
    header.writeln('=' * 60);
    header.writeln('');

    await _logFile!.writeAsString(header.toString());
  }

  /// 写入日志行到文件
  Future<void> writeLogLine(String line) async {
    if (_logFile == null) return;

    try {
      await _logFile!
          .writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      onLogError?.call('写入日志文件失败', error: e);
      // 如果写入失败，清空文件引用
      _logFile = null;
    }
  }

  /// 获取当前日志文件路径
  String? get logFilePath => _logFile?.path;

  /// 获取所有日志文件
  Future<List<File>> getLogFiles() async {
    try {
      if (_logsDir == null) {
        final logsDirPath = await getLogsDirectoryPath();
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
      onLogError?.call('获取日志文件列表失败', error: e);
      return [];
    }
  }

  /// 清理旧日志（保留最近N个，单个文件最大M，总大小最大T）
  Future<void> _cleanOldLogs() async {
    try {
      final files = await getLogFiles();
      if (files.isEmpty) {
        return;
      }

      // 按修改时间排序（最新的在前）
      files
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      int totalSize = 0;
      int keptCount = 0;

      for (var file in files) {
        final size = await file.length();

        // 如果文件超过最大大小，删除
        if (size > maxFileSize) {
          await file.delete();
          continue;
        }

        // 如果总大小超过限制，删除
        if (totalSize + size > maxTotalSize) {
          await file.delete();
          continue;
        }

        // 如果保留的文件超过限制，删除
        if (keptCount >= maxFiles) {
          await file.delete();
          continue;
        }

        totalSize += size;
        keptCount++;
      }
    } catch (e) {
      onLogError?.call('清理旧日志失败', error: e);
    }
  }

  /// 清理旧日志（公开方法，供UI调用）
  Future<void> cleanOldLogs() async {
    await _cleanOldLogs();
  }

  /// 清理所有日志（公开方法）
  Future<void> cleanAllLogs() async {
    try {
      if (_logsDir == null) {
        final logsDirPath = await getLogsDirectoryPath();
        _logsDir = Directory(logsDirPath);
      }

      if (!await _logsDir!.exists()) {
        return;
      }

      final files = await getLogFiles();

      for (var file in files) {
        await file.delete();
      }
    } catch (e, stackTrace) {
      onLogError?.call('清理所有日志失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
