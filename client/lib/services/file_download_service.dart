import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:async';
import 'logger_service.dart';

/// 下载任务内部类
class _DownloadTask {
  final String url;
  final String filePath;
  final String? fileName;
  final Function(int received, int total)? onProgress;
  final Completer<String> completer;
  int downloadedBytes = 0;
  
  _DownloadTask({
    required this.url,
    required this.filePath,
    this.fileName,
    this.onProgress,
    required this.completer,
  });
}

/// 通用的文件下载服务
/// 支持断点续传和并发下载（最多2个线程）
class FileDownloadService {
  final Dio _dio = Dio();
  final ClientLoggerService _logger = ClientLoggerService();
  
  // 最大并发下载数
  static const int maxConcurrentDownloads = 2;
  
  // 当前活跃的下载任务
  final Set<String> _activeDownloads = {};
  
  // 等待队列
  final List<_DownloadTask> _waitingQueue = [];

  /// 下载文件（支持断点续传）
  /// 
  /// [url] 下载URL
  /// [fileName] 保存的文件名（可选，如果不提供则从URL提取）
  /// [onProgress] 进度回调 (received, total)
  /// 
  /// 返回下载文件的路径
  Future<String> downloadFile({
    required String url,
    String? fileName,
    Function(int received, int total)? onProgress,
  }) async {
    try {
      _logger.log('开始下载文件: $url', tag: 'DOWNLOAD');
      
      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();
      await Directory(downloadDir).create(recursive: true);
      
      // 确定文件名
      String finalFileName = fileName ?? path.basename(url);
      if (finalFileName.isEmpty) {
        finalFileName = 'download_${DateTime.now().millisecondsSinceEpoch}';
      }
      
      final filePath = path.join(downloadDir, finalFileName);
      _logger.log('保存路径: $filePath', tag: 'DOWNLOAD');
      
      // 检查文件是否已存在（断点续传）
      int startByte = 0;
      final file = File(filePath);
      if (await file.exists()) {
        startByte = await file.length();
        _logger.log('发现已存在的文件，从字节 $startByte 继续下载', tag: 'DOWNLOAD');
      }
      
      // 创建下载任务
      final completer = Completer<String>();
      final task = _DownloadTask(
        url: url,
        filePath: filePath,
        fileName: fileName,
        onProgress: onProgress,
        completer: completer,
      );
      task.downloadedBytes = startByte;
      
      // 如果已达到最大并发数，加入等待队列
      if (_activeDownloads.length >= maxConcurrentDownloads) {
        _waitingQueue.add(task);
        _logger.log('下载任务已加入等待队列，当前活跃数: ${_activeDownloads.length}', tag: 'DOWNLOAD');
      } else {
        _startDownload(task);
      }
      
      return await completer.future;
    } catch (e, stackTrace) {
      _logger.logError('下载文件失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
  
  /// 开始下载任务
  Future<void> _startDownload(_DownloadTask task) async {
    _activeDownloads.add(task.url);
    
    try {
      final file = File(task.filePath);
      final fileExists = await file.exists();
      
      // 设置Range头支持断点续传
      final headers = <String, dynamic>{
        'Accept': '*/*',
      };
      if (fileExists && task.downloadedBytes > 0) {
        headers['Range'] = 'bytes=${task.downloadedBytes}-';
        _logger.log('使用断点续传，从字节 ${task.downloadedBytes} 开始', tag: 'DOWNLOAD');
      }
      
      // 下载文件（Dio会自动处理断点续传）
      await _dio.download(
        task.url,
        task.filePath,
        onReceiveProgress: (received, total) {
          // 计算实际接收的字节数（考虑断点续传）
          final actualReceived = task.downloadedBytes + received;
          final actualTotal = task.downloadedBytes + (total > 0 ? total : 0);
          
          if (task.onProgress != null) {
            task.onProgress!(actualReceived, actualTotal);
          }
          
          if (actualTotal > 0) {
            final percent = (actualReceived / actualTotal * 100).toStringAsFixed(1);
            _logger.log('下载进度: $percent% ($actualReceived/$actualTotal)', tag: 'DOWNLOAD');
          }
        },
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(minutes: 30), // 30分钟超时
        ),
        deleteOnError: false, // 保留部分下载的文件
      );
      
      // 验证文件是否存在
      if (await file.exists()) {
        final fileSize = await file.length();
        _logger.log('文件下载完成: ${task.filePath}, 大小: $fileSize 字节', tag: 'DOWNLOAD');
        task.completer.complete(task.filePath);
      } else {
        throw Exception('文件下载完成但文件不存在');
      }
    } catch (e, stackTrace) {
      _logger.logError('下载文件失败', error: e, stackTrace: stackTrace);
      task.completer.completeError(e);
    } finally {
      _activeDownloads.remove(task.url);
      _tryStartNext();
    }
  }
  
  /// 尝试启动下一个等待中的下载任务
  void _tryStartNext() {
    if (_waitingQueue.isNotEmpty && _activeDownloads.length < maxConcurrentDownloads) {
      final nextTask = _waitingQueue.removeAt(0);
      _startDownload(nextTask);
    }
  }

  /// 获取下载目录（公开方法供UpdateService使用）
  Future<String> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Android: 使用应用外部存储目录
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        return path.join(directory.path, 'Downloads');
      }
      // 如果外部存储不可用，使用应用内部目录
      final appDir = await getApplicationDocumentsDirectory();
      return path.join(appDir.path, 'Downloads');
    } else if (Platform.isIOS) {
      // iOS: 使用应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      return path.join(directory.path, 'Downloads');
    } else if (Platform.isMacOS) {
      // macOS: 使用用户下载目录
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        return directory.path;
      }
      // 如果不可用，使用应用支持目录
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'Downloads');
    } else if (Platform.isWindows) {
      // Windows: 使用用户下载目录
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        return directory.path;
      }
      // 如果不可用，使用应用数据目录
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'Downloads');
    } else {
      // 其他平台：使用应用支持目录
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'Downloads');
    }
  }
}

