import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class ClientLoggerService {
  static final ClientLoggerService _instance = ClientLoggerService._internal();
  factory ClientLoggerService() => _instance;
  ClientLoggerService._internal();

  static const String _debugModeKey = 'client_debug_mode_enabled';
  
  File? _logFile;
  bool _initialized = false;
  bool _debugEnabled = true; // 默认启用日志
  Directory? _logsDir;
  
  bool get debugEnabled => _debugEnabled;

  // 初始化日志服务
  Future<void> initialize() async {
    if (_initialized) {
      print('[LOGGER] 日志服务已初始化，跳过');
      return;
    }
    
    try {
      print('[LOGGER] ========== 开始初始化客户端日志服务 ==========');
      
      // 从SharedPreferences读取调试模式设置
      final prefs = await SharedPreferences.getInstance();
      _debugEnabled = prefs.getBool(_debugModeKey) ?? true; // 默认true
      print('[LOGGER] 调试模式: $_debugEnabled');
      
      if (!_debugEnabled) {
        print('[LOGGER] 调试模式已禁用，仅输出到控制台');
        _initialized = true;
        return;
      }
      
      // 初始化日志目录和文件
      await _initLogDirectory();
      await _initLogFile();
      
      _initialized = true;
      print('[LOGGER] ✓ 日志服务初始化成功');
      
      // 写入初始日志
      log('客户端日志系统初始化成功', tag: 'INIT');
      if (_logFile != null) {
        log('日志文件: ${_logFile!.path}', tag: 'INIT');
      }
    } catch (e, stackTrace) {
      print('[LOGGER] ✗ 初始化日志文件失败: $e');
      print('[LOGGER] ✗ 堆栈: $stackTrace');
      _initialized = false;
      rethrow; // 重新抛出异常，让调用者知道初始化失败
    }
  }

  // 测试写入权限
  Future<bool> _testWritePermission(Directory dir) async {
    try {
      final testFile = File(path.join(dir.path, '.test_write_${DateTime.now().millisecondsSinceEpoch}'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (e) {
      print('[LOGGER] 写入权限测试失败: $e');
      return false;
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
    } else {
      // 如果禁用调试模式，关闭日志文件
      _logFile = null;
    }
  }

  // 初始化日志目录（内部方法）
  Future<void> _initLogDirectory() async {
    // 检查应用是否为沙盒应用
    final Directory appSupportDir = await getApplicationSupportDirectory();
    print('[LOGGER] Application Support目录: ${appSupportDir.path}');
    
    String logsDirPath;
    
    // 判断是否为沙盒应用：沙盒应用的Application Support路径包含Containers
    if (appSupportDir.path.contains('/Containers/')) {
      // 沙盒应用：日志存储在 ~/Library/Containers/<Bundle ID>/Data/Library/Logs/
      print('[LOGGER] 检测到沙盒应用');
      final String appSupportPath = appSupportDir.path;
      // 从 Application Support 构建到 Library/Logs
      final String libraryPath = appSupportPath.replaceAll('/Application Support/com.example.remoteCamClient', '');
      logsDirPath = path.join(libraryPath, 'Logs');
    } else {
      // 非沙盒应用：日志存储在 ~/Library/Logs/<应用名称>/
      print('[LOGGER] 检测到非沙盒应用');
      final String homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) {
        throw Exception('无法获取用户主目录');
      }
      // 使用应用名称作为日志目录名
      logsDirPath = path.join(homeDir, 'Library', 'Logs', 'remote_cam_client');
    }
    
    _logsDir = Directory(logsDirPath);
    
    print('[LOGGER] 日志目录路径: $logsDirPath');
    
    // 确保日志目录存在
    if (!await _logsDir!.exists()) {
      print('[LOGGER] 日志目录不存在，正在创建: $logsDirPath');
      await _logsDir!.create(recursive: true);
      print('[LOGGER] 日志目录创建成功');
    } else {
      print('[LOGGER] 日志目录已存在: $logsDirPath');
    }
    
    // 验证目录权限
    final canWrite = await _testWritePermission(_logsDir!);
    if (!canWrite) {
      print('[LOGGER] 错误: 无法写入日志目录');
      throw Exception('无法写入日志目录: $logsDirPath');
    }
    print('[LOGGER] 目录权限验证通过');
  }

  // 初始化日志文件（内部方法）
  Future<void> _initLogFile() async {
    try {
      if (_logsDir == null) {
        await _initLogDirectory();
      }
      
      // 清理旧日志（在创建新日志之前）
      await _cleanOldLogs();
      
      // 创建新的日志文件（每次启动都创建新文件）
      final String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final String filePath = path.join(_logsDir!.path, 'client_debug_$timestamp.log');
      
      _logFile = File(filePath);
      
      // 写入文件头
      final Directory appSupportDir = await getApplicationSupportDirectory();
      await _logFile!.writeAsString('=== Remote Cam Client Debug Log ===\n');
      await _logFile!.writeAsString('Started at: ${DateTime.now()}\n');
      await _logFile!.writeAsString('Platform: ${Platform.operatingSystem}\n');
      await _logFile!.writeAsString('App Support Dir: ${appSupportDir.path}\n');
      await _logFile!.writeAsString('Log Dir: ${_logsDir!.path}\n');
      await _logFile!.writeAsString('Log File: $filePath\n');
      await _logFile!.writeAsString('=' * 60 + '\n\n');
      
      print('[LOGGER] ✓ 日志文件初始化成功: $filePath');
    } catch (e, stackTrace) {
      print('[LOGGER] ✗ 初始化日志文件失败: $e');
      print('[LOGGER] ✗ 堆栈: $stackTrace');
      _logFile = null;
    }
  }

  // 记录日志
  void log(String message, {String? tag}) {
    final timestamp = DateTime.now().toString();
    final tagStr = tag != null ? '[$tag] ' : '';
    final line = '[$timestamp] $tagStr$message\n';
    
    // 打印到控制台
    print('$tagStr$message');
    
    // 写入文件（仅在调试模式启用时）
    if (_debugEnabled && _initialized && _logFile != null) {
      try {
        _logFile!.writeAsStringSync(line, mode: FileMode.append, flush: true);
      } catch (e) {
        print('[LOGGER] 写入日志失败: $e');
        // 尝试重新初始化
        _initialized = false;
      }
    }
  }

  // API调用日志（增强版，记录更多详情）
  void logApiCall(String method, String endpoint, {Map<String, dynamic>? params, Map<String, String>? headers, String? body}) {
    final paramsStr = params != null ? '\n参数: $params' : '';
    final headersStr = headers != null && headers.isNotEmpty ? '\n请求头: $headers' : '';
    final bodyStr = body != null ? '\n请求体: $body' : '';
    log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'API');
    log('→ API调用: $method $endpoint$paramsStr$headersStr$bodyStr', tag: 'API');
  }

  // API响应日志（增强版，记录更多详情）
  void logApiResponse(String endpoint, int statusCode, {dynamic body, String? error}) {
    final bodyStr = body != null ? '\n响应体: $body' : '';
    final errorStr = error != null ? '\n错误: $error' : '';
    final statusIcon = statusCode >= 200 && statusCode < 300 ? '✓' : '✗';
    log('$statusIcon API响应: $endpoint -> HTTP $statusCode$bodyStr$errorStr', tag: 'API');
    log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'API');
  }
  
  // 指令记录（记录所有发送到服务端的指令）
  void logCommand(String command, {Map<String, dynamic>? params, String? details}) {
    final paramsStr = params != null ? '\n参数: $params' : '';
    final detailsStr = details != null ? '\n详情: $details' : '';
    log('📤 发送指令: $command$paramsStr$detailsStr', tag: 'COMMAND');
  }
  
  // 指令响应记录
  void logCommandResponse(String command, {bool success = true, dynamic result, String? error}) {
    final icon = success ? '✓' : '✗';
    final resultStr = result != null ? '\n结果: $result' : '';
    final errorStr = error != null ? '\n错误: $error' : '';
    log('$icon 指令响应: $command -> ${success ? "成功" : "失败"}$resultStr$errorStr', tag: 'COMMAND');
  }

  // 下载日志
  void logDownload(String action, {String? details}) {
    log('下载: $action${details != null ? " - $details" : ""}', tag: 'DOWNLOAD');
  }

  // 错误日志
  void logError(String message, {Object? error, StackTrace? stackTrace}) {
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
    log('连接: $action${details != null ? " - $details" : ""}', tag: 'CONNECTION');
  }

  // 获取日志文件路径
  String? get logFilePath => _logFile?.path;

  // 获取所有日志文件
  Future<List<File>> getLogFiles() async {
    try {
      if (_logsDir == null) {
        // 重新构建日志目录路径
        final Directory appSupportDir = await getApplicationSupportDirectory();
        String logsDirPath;
        
        if (appSupportDir.path.contains('/Containers/')) {
          // 沙盒应用
          final String appSupportPath = appSupportDir.path;
          final String libraryPath = appSupportPath.replaceAll('/Application Support/com.example.remoteCamClient', '');
          logsDirPath = path.join(libraryPath, 'Logs');
        } else {
          // 非沙盒应用
          final String homeDir = Platform.environment['HOME'] ?? '';
          logsDirPath = path.join(homeDir, 'Library', 'Logs', 'remote_cam_client');
        }
        
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
      print('[LOGGER] 获取日志文件列表失败: $e');
      return [];
    }
  }

  // 清理旧日志（保留最近10个，单个文件最大10MB，总大小最大50MB）
  Future<void> _cleanOldLogs() async {
    try {
      final files = await getLogFiles();
      if (files.isEmpty) {
        print('[LOGGER] 没有旧日志文件需要清理');
        return;
      }
      
      print('[LOGGER] 找到 ${files.length} 个日志文件，开始清理...');
      
      // 按修改时间排序（最新的在前）
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      
      int totalSize = 0;
      int keptCount = 0;
      int deletedCount = 0;
      
      for (var file in files) {
        final size = await file.length();
        
        // 如果文件超过10MB，删除
        if (size > 10 * 1024 * 1024) {
          print('[LOGGER] 删除超大日志文件: ${file.path} (${(size / 1024 / 1024).toStringAsFixed(2)}MB)');
          await file.delete();
          deletedCount++;
          continue;
        }
        
        // 如果总大小超过50MB，删除
        if (totalSize + size > 50 * 1024 * 1024) {
          print('[LOGGER] 删除日志文件（总大小限制）: ${file.path}');
          await file.delete();
          deletedCount++;
          continue;
        }
        
        // 如果保留的文件超过10个，删除
        if (keptCount >= 10) {
          print('[LOGGER] 删除旧日志文件: ${file.path}');
          await file.delete();
          deletedCount++;
          continue;
        }
        
        totalSize += size;
        keptCount++;
      }
      
      print('[LOGGER] 日志清理完成: 保留 $keptCount 个，删除 $deletedCount 个');
    } catch (e) {
      print('[LOGGER] 清理旧日志失败: $e');
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
        // 重新构建日志目录路径
        final Directory appSupportDir = await getApplicationSupportDirectory();
        String logsDirPath;
        
        if (appSupportDir.path.contains('/Containers/')) {
          // 沙盒应用
          final String appSupportPath = appSupportDir.path;
          final String libraryPath = appSupportPath.replaceAll('/Application Support/com.example.remoteCamClient', '');
          logsDirPath = path.join(libraryPath, 'Logs');
        } else {
          // 非沙盒应用
          final String homeDir = Platform.environment['HOME'] ?? '';
          logsDirPath = path.join(homeDir, 'Library', 'Logs', 'remote_cam_client');
        }
        
        _logsDir = Directory(logsDirPath);
      }
      
      if (!await _logsDir!.exists()) {
        print('[LOGGER] 日志目录不存在，无需清理');
        return;
      }
      
      final files = await getLogFiles();
      print('[LOGGER] 清理所有日志文件，共 ${files.length} 个');
      
      for (var file in files) {
        await file.delete();
      }
      
      print('[LOGGER] 所有日志文件已清理');
    } catch (e) {
      print('[LOGGER] 清理所有日志失败: $e');
      rethrow;
    }
  }
}

