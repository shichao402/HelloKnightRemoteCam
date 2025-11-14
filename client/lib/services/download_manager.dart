import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/download_task.dart';
import 'download_settings_service.dart';

class DownloadManager {
  static const int maxConcurrent = 2; // 最大并发下载数
  static const int maxRetries = 3;    // 最大重试次数

  final String baseUrl;
  
  Database? _database;
  final Dio _dio = Dio();
  final DownloadSettingsService _settingsService = DownloadSettingsService();
  
  final Queue<DownloadTask> _waitingQueue = Queue();
  final List<DownloadTask> _activeDownloads = [];
  final Map<String, CancelToken> _cancelTokens = {};
  
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();

  DownloadManager({
    required this.baseUrl,
  });

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;

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
    // 生成任务ID
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();

    // 获取保存路径（使用设置的路径）
    final downloadDir = await _settingsService.getDownloadPath();
    await Directory(downloadDir).create(recursive: true);
    final localPath = path.join(downloadDir, fileName);

    // 获取文件大小
    int totalBytes = 0;
    try {
      final response = await _dio.head(
        '$baseUrl/file/download?path=${Uri.encodeComponent(remoteFilePath)}',
        options: Options(),
      );
      totalBytes = int.parse(response.headers['content-length']?[0] ?? '0');
    } catch (e) {
      print('获取文件大小失败: $e');
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

    // 添加到队列
    _waitingQueue.add(task);
    _notifyTasksChanged();

    // 尝试开始下载
    _tryStartNext();

    return taskId;
  }

  // 尝试启动下一个任务
  void _tryStartNext() {
    while (_activeDownloads.length < maxConcurrent && _waitingQueue.isNotEmpty) {
      final task = _waitingQueue.removeFirst();
      _activeDownloads.add(task);
      _startDownload(task);
    }
  }

  // 开始下载
  Future<void> _startDownload(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    task.startTime = DateTime.now();
    await _updateTask(task);
    _notifyTasksChanged();

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final url = '$baseUrl/file/download?path=${Uri.encodeComponent(task.remoteFilePath)}';
      
      await _dio.download(
        url,
        task.localFilePath,
        onReceiveProgress: (received, total) {
          task.downloadedBytes = received;
          task.totalBytes = total;
          _updateTask(task);
          _notifyTasksChanged();
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

      // 下载成功
      task.status = DownloadStatus.completed;
      task.endTime = DateTime.now();
      await _updateTask(task);
      _onComplete(task);
    } catch (e) {
      // 下载失败
      task.errorMessage = e.toString();
      
      if (task.retryCount < maxRetries && !cancelToken.isCancelled) {
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
        print('删除文件失败: $e');
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
    await _database?.close();
  }
}

