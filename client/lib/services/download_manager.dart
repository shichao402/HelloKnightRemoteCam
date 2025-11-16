import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/download_task.dart';
import 'download_settings_service.dart';
import 'logger_service.dart';

class DownloadManager {
  static const int maxConcurrent = 2; // 最大并发下载数
  static const int maxRetries = 3;    // 最大重试次数

  final String baseUrl;
  
  Database? _database;
  final Dio _dio = Dio();
  final DownloadSettingsService _settingsService = DownloadSettingsService();
  final ClientLoggerService _logger = ClientLoggerService();
  
  final Queue<DownloadTask> _waitingQueue = Queue();
  final List<DownloadTask> _activeDownloads = [];
  final Map<String, CancelToken> _cancelTokens = {};
  
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();
  
  // 下载完成回调流（通知下载完成事件）
  final StreamController<DownloadTask> _completionController =
      StreamController<DownloadTask>.broadcast();

  DownloadManager({
    required this.baseUrl,
  });

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  
  // 下载完成事件流
  Stream<DownloadTask> get completionStream => _completionController.stream;

  // 获取所有任务（包括等待、下载中）
  List<DownloadTask> getTasks() {
    final allTasks = <DownloadTask>[];
    allTasks.addAll(_waitingQueue);
    allTasks.addAll(_activeDownloads);
    return allTasks;
  }
  
  // 根据文件名查找任务（包括已完成的任务）
  Future<DownloadTask?> findTaskByFileName(String fileName) async {
    // 先检查内存中的任务
    try {
      final memoryTask = [..._waitingQueue, ..._activeDownloads].firstWhere(
        (t) => t.fileName == fileName,
      );
      return memoryTask;
    } catch (e) {
      // 内存中没有找到
    }
    
    // 检查数据库中的已完成任务
    if (_database != null) {
      try {
        final List<Map<String, dynamic>> maps = await _database!.query(
          'downloads',
          where: 'fileName = ? AND status = ?',
          whereArgs: [fileName, DownloadStatus.completed.toString()],
        );
        
        if (maps.isNotEmpty) {
          return DownloadTask.fromJson(maps.first);
        }
      } catch (e) {
        // 忽略错误
      }
    }
    
    return null;
  }

  // 初始化数据库
  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    final dbFile = path.join(dbPath, 'downloads.db');

    _database = await openDatabase(
      dbFile,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE downloads (
            id TEXT PRIMARY KEY,
            remoteFilePath TEXT,
            localFilePath TEXT,
            fileName TEXT,
            totalBytes INTEGER,
            downloadedBytes INTEGER,
            status TEXT,
            retryCount INTEGER,
            startTime TEXT,
            endTime TEXT,
            errorMessage TEXT
          )
        ''');
      },
    );

    // 加载未完成的任务
    await _loadPendingTasks();
  }

  // 加载待完成的任务
  Future<void> _loadPendingTasks() async {
    if (_database == null) return;

    final List<Map<String, dynamic>> maps = await _database!.query(
      'downloads',
      where: 'status != ?',
      whereArgs: ['DownloadStatus.completed'],
    );

    for (var map in maps) {
      final task = DownloadTask.fromJson(map);
      if (task.status == DownloadStatus.downloading) {
        // 重置为待处理状态
        task.status = DownloadStatus.pending;
      }
      _waitingQueue.add(task);
    }

    if (_waitingQueue.isNotEmpty) {
      _tryStartNext();
    }
  }

  // 添加下载任务
  Future<String> addDownload({
    required String remoteFilePath,
    required String fileName,
  }) async {
    _logger.logDownload('添加下载任务', details: fileName);
    // 生成任务ID
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();

    // 获取保存路径（使用设置的路径）
    final downloadDir = await _settingsService.getDownloadPath();
    await Directory(downloadDir).create(recursive: true);
    final localPath = path.join(downloadDir, fileName);
    _logger.log('下载路径: $localPath', tag: 'DOWNLOAD');

    // 获取文件大小
    int totalBytes = 0;
    try {
      _logger.log('发送HEAD请求获取文件大小: $remoteFilePath', tag: 'DOWNLOAD');
      final response = await _dio.head(
        '$baseUrl/file/download?path=${Uri.encodeComponent(remoteFilePath)}',
        options: Options(),
      );
      
      // 记录响应状态码和所有响应头
      _logger.log('HEAD响应状态码: ${response.statusCode}', tag: 'DOWNLOAD');
      _logger.log('HEAD响应头: ${response.headers.map}', tag: 'DOWNLOAD');
      
      // 尝试多种方式获取Content-Length
      String? contentLengthStr;
      
      // 方式1: 使用value方法（推荐）
      try {
        contentLengthStr = response.headers.value('content-length');
        _logger.log('方式1获取Content-Length: $contentLengthStr', tag: 'DOWNLOAD');
      } catch (e) {
        _logger.log('方式1失败: $e', tag: 'DOWNLOAD');
      }
      
      // 方式2: 使用map访问（大小写不敏感）
      if (contentLengthStr == null || contentLengthStr.isEmpty) {
        try {
          final headerList = response.headers['content-length'];
          if (headerList != null && headerList.isNotEmpty) {
            contentLengthStr = headerList[0];
            _logger.log('方式2获取Content-Length: $contentLengthStr', tag: 'DOWNLOAD');
          }
        } catch (e) {
          _logger.log('方式2失败: $e', tag: 'DOWNLOAD');
        }
      }
      
      // 方式3: 尝试不同的大小写
      if (contentLengthStr == null || contentLengthStr.isEmpty) {
        try {
          contentLengthStr = response.headers.value('Content-Length');
          _logger.log('方式3获取Content-Length: $contentLengthStr', tag: 'DOWNLOAD');
        } catch (e) {
          _logger.log('方式3失败: $e', tag: 'DOWNLOAD');
        }
      }
      
      if (contentLengthStr != null && contentLengthStr.isNotEmpty) {
        totalBytes = int.tryParse(contentLengthStr) ?? 0;
        _logger.log('解析后的文件大小: $totalBytes 字节', tag: 'DOWNLOAD');
      } else {
        _logger.log('警告: 无法从响应头获取Content-Length，使用默认值0', tag: 'DOWNLOAD');
        totalBytes = 0;
      }
      
      _logger.log('最终文件大小: $totalBytes 字节', tag: 'DOWNLOAD');
    } catch (e, stackTrace) {
      _logger.logError('获取文件大小失败', error: e, stackTrace: stackTrace);
    }

    // 创建任务
    final task = DownloadTask(
      id: taskId,
      remoteFilePath: remoteFilePath,
      localFilePath: localPath,
      fileName: fileName,
      totalBytes: totalBytes,
    );

    // 保存到数据库
    await _saveTask(task);
    _logger.log('任务已保存到数据库: $taskId', tag: 'DOWNLOAD');

    // 添加到队列
    _waitingQueue.add(task);
    _notifyTasksChanged();
    _logger.log('任务已添加到队列，等待队列长度: ${_waitingQueue.length}', tag: 'DOWNLOAD');

    // 尝试开始下载
    _tryStartNext();

    return taskId;
  }

  // 尝试启动下一个任务
  void _tryStartNext() {
    while (_activeDownloads.length < maxConcurrent && _waitingQueue.isNotEmpty) {
      final task = _waitingQueue.removeFirst();
      _activeDownloads.add(task);
      _logger.log('启动下载任务: ${task.fileName}, 当前活跃下载数: ${_activeDownloads.length}', tag: 'DOWNLOAD');
      _startDownload(task);
    }
  }

  // 开始下载
  Future<void> _startDownload(DownloadTask task) async {
    _logger.logDownload('开始下载', details: '${task.fileName}, 总大小: ${task.totalBytes} 字节');
    task.status = DownloadStatus.downloading;
    task.startTime = DateTime.now();
    await _updateTask(task);
    _notifyTasksChanged(); // 立即通知，确保UI显示下载状态
    _logger.log('已通知UI下载开始: ${task.fileName}', tag: 'DOWNLOAD');

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final url = '$baseUrl/file/download?path=${Uri.encodeComponent(task.remoteFilePath)}';
      
      // 记录上次更新的进度，用于控制更新频率
      int lastNotifiedBytes = 0;
      DateTime lastNotifyTime = DateTime.now();
      bool hasNotifiedProgress = false; // 标记是否已经通知过进度
      
      await _dio.download(
        url,
        task.localFilePath,
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final timeDiff = now.difference(lastNotifyTime);
          
          // 更新任务数据
          task.downloadedBytes = received;
          // 如果之前 totalBytes 为 0，现在有正确的 total 值，立即更新并通知UI
          final totalBytesChanged = task.totalBytes == 0 && total > 0;
          task.totalBytes = total;
          
          // 每500ms更新一次，或者下载完成时更新，或者 totalBytes 从0变为正确值时立即更新
          final shouldNotify = timeDiff.inMilliseconds >= 500 || 
                               received == total ||
                               !hasNotifiedProgress ||
                               totalBytesChanged;
          
          if (shouldNotify) {
            final progressPercent = total > 0 ? (received * 100 / total).round() : 0;
            // 优化：只在调试模式下记录详细日志，减少日志开销
            if (totalBytesChanged) {
              _logger.log('进度更新(总大小已更新): ${task.fileName}, $received/$total 字节 ($progressPercent%), 时间差: ${timeDiff.inMilliseconds}ms', tag: 'DOWNLOAD');
            } else {
              // 只在进度变化较大时记录日志（减少日志量）
              final progressDiff = (received - lastNotifiedBytes) * 100 / total;
              if (progressDiff >= 5 || received == total) {
                _logger.log('进度更新: ${task.fileName}, $received/$total 字节 ($progressPercent%), 时间差: ${timeDiff.inMilliseconds}ms', tag: 'DOWNLOAD');
              }
            }
            _updateTask(task);
            _notifyTasksChanged(); // 通知UI更新
            lastNotifiedBytes = received;
            lastNotifyTime = now;
            hasNotifiedProgress = true;
          }
        },
        options: Options(
          headers: {
            if (task.downloadedBytes > 0)
              'Range': 'bytes=${task.downloadedBytes}-',
          },
        ),
        cancelToken: cancelToken,
        deleteOnError: false, // 保留部分下载的文件
      );

      // 下载成功 - 确保进度显示为100%
      _logger.logDownload('下载完成', details: '${task.fileName}, 最终大小: ${task.downloadedBytes}/${task.totalBytes}');
      task.downloadedBytes = task.totalBytes; // 确保进度为100%
      task.status = DownloadStatus.completed;
      task.endTime = DateTime.now();
      await _updateTask(task);
      _notifyTasksChanged(); // 通知UI更新，显示100%进度
      _logger.log('已通知UI下载完成(100%): ${task.fileName}', tag: 'DOWNLOAD');
      
      // 验证文件确实存在（确保文件已完全写入）
      final file = File(task.localFilePath);
      int retryCount = 0;
      const maxRetries = 10; // 最多重试10次
      const retryDelay = Duration(milliseconds: 100);
      
      while (!await file.exists() && retryCount < maxRetries) {
        await Future.delayed(retryDelay);
        retryCount++;
      }
      
      if (await file.exists()) {
        // 文件已确认存在，触发完成回调
        _logger.log('文件验证成功: ${task.fileName}', tag: 'DOWNLOAD');
        _onComplete(task);
      } else {
        // 文件不存在，标记为失败
        _logger.logError('文件验证失败: ${task.fileName}', error: '文件下载完成但文件不存在');
        task.status = DownloadStatus.failed;
        task.errorMessage = '文件下载完成但文件不存在';
        await _updateTask(task);
        _notifyTasksChanged(); // 通知UI更新失败状态
        _onComplete(task);
      }
    } catch (e) {
      // 下载失败
      task.errorMessage = e.toString();
      
      if (task.retryCount < DownloadManager.maxRetries && !cancelToken.isCancelled) {
        // 重试
        task.retryCount++;
        task.status = DownloadStatus.pending;
        await _updateTask(task);
        
        // 延迟后重新加入队列
        await Future.delayed(Duration(seconds: 2 * task.retryCount));
        _waitingQueue.add(task);
        _activeDownloads.remove(task);
        _tryStartNext();
      } else {
        // 失败
        task.status = DownloadStatus.failed;
        task.endTime = DateTime.now();
        await _updateTask(task);
        _onComplete(task);
      }
    } finally {
      _cancelTokens.remove(task.id);
    }

    _notifyTasksChanged();
  }

  // 下载完成回调
  void _onComplete(DownloadTask task) {
    _activeDownloads.remove(task);
    _notifyTasksChanged();
    
    // 如果下载成功，发送完成事件
    if (task.status == DownloadStatus.completed) {
      _completionController.add(task);
    }
    
    _tryStartNext(); // 启动下一个
  }

  // 暂停下载
  Future<void> pauseDownload(String taskId) async {
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null) {
      cancelToken.cancel('用户暂停');
    }

    final task = _findTask(taskId);
    if (task != null) {
      task.status = DownloadStatus.paused;
      await _updateTask(task);
      _activeDownloads.remove(task);
      _notifyTasksChanged();
      _tryStartNext();
    }
  }

  // 恢复下载
  Future<void> resumeDownload(String taskId) async {
    final task = _findTask(taskId);
    if (task != null && task.status == DownloadStatus.paused) {
      task.status = DownloadStatus.pending;
      task.retryCount = 0; // 重置重试次数
      await _updateTask(task);
      _waitingQueue.add(task);
      _notifyTasksChanged();
      _tryStartNext();
    }
  }

  // 取消下载
  Future<void> cancelDownload(String taskId) async {
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null) {
      cancelToken.cancel('用户取消');
    }

    final task = _findTask(taskId);
    if (task != null) {
      _activeDownloads.remove(task);
      _waitingQueue.remove(task);
      
      // 删除部分下载的文件
      try {
        final file = File(task.localFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        _logger.logError('删除文件失败', error: e);
      }

      // 从数据库删除
      await _deleteTask(taskId);
      _notifyTasksChanged();
      _tryStartNext();
    }
  }

  // 重试失败的下载
  Future<void> retryDownload(String taskId) async {
    final task = _findTask(taskId);
    if (task != null && task.canRetry) {
      task.status = DownloadStatus.pending;
      task.errorMessage = null;
      await _updateTask(task);
      _waitingQueue.add(task);
      _notifyTasksChanged();
      _tryStartNext();
    }
  }

  // 获取所有任务
  List<DownloadTask> getAllTasks() {
    final allTasks = <DownloadTask>[];
    allTasks.addAll(_activeDownloads);
    allTasks.addAll(_waitingQueue);
    return allTasks;
  }

  // 获取已完成的任务（从数据库）
  Future<List<DownloadTask>> getCompletedTasks() async {
    if (_database == null) return [];
    
    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'downloads',
        where: 'status = ?',
        whereArgs: [DownloadStatus.completed.toString()],
        orderBy: 'endTime DESC',
      );
      
      return maps.map((map) => DownloadTask.fromJson(map)).toList();
    } catch (e) {
      _logger.logError('获取已完成任务失败', error: e);
      return [];
    }
  }

  // 删除指定天数之前的已完成任务
  Future<int> deleteCompletedTasksOlderThan(int days) async {
    if (_database == null) return 0;
    
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: days));
      final cutoffDateStr = cutoffDate.toIso8601String();
      
      final deletedCount = await _database!.delete(
        'downloads',
        where: 'status = ? AND endTime < ?',
        whereArgs: [DownloadStatus.completed.toString(), cutoffDateStr],
      );
      
      return deletedCount;
    } catch (e) {
      _logger.logError('删除旧任务失败', error: e);
      return 0;
    }
  }

  // 删除指定的已完成任务
  Future<bool> deleteCompletedTask(String taskId) async {
    if (_database == null) return false;
    
    try {
      final deletedCount = await _database!.delete(
        'downloads',
        where: 'id = ? AND status = ?',
        whereArgs: [taskId, DownloadStatus.completed.toString()],
      );
      
      return deletedCount > 0;
    } catch (e) {
      _logger.logError('删除任务失败', error: e);
      return false;
    }
  }

  // 查找任务
  DownloadTask? _findTask(String taskId) {
    try {
      return _activeDownloads.firstWhere((t) => t.id == taskId);
    } catch (e) {
      try {
        return _waitingQueue.firstWhere((t) => t.id == taskId);
      } catch (e) {
        return null;
      }
    }
  }

  // 保存任务到数据库
  Future<void> _saveTask(DownloadTask task) async {
    if (_database == null) return;
    await _database!.insert(
      'downloads',
      task.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 更新任务
  Future<void> _updateTask(DownloadTask task) async {
    if (_database == null) return;
    await _database!.update(
      'downloads',
      task.toJson(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  // 删除任务
  Future<void> _deleteTask(String taskId) async {
    if (_database == null) return;
    await _database!.delete(
      'downloads',
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  // 通知任务列表变化
  void _notifyTasksChanged() {
    _tasksController.add(getAllTasks());
  }

  // 清理资源
  Future<void> dispose() async {
    for (var token in _cancelTokens.values) {
      token.cancel('DownloadManager disposed');
    }
    await _tasksController.close();
    await _completionController.close();
    await _database?.close();
  }
}

