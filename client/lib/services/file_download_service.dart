import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'dart:async';
import 'logger_service.dart';
import 'download_directory_service.dart';

/// 下载任务内部类
class _DownloadTask {
  final String url;
  final String filePath;
  final String? fileName;
  final Function(int received, int total)? onProgress;
  final Function(String status)? onStatus;
  final Completer<String> completer;
  int downloadedBytes = 0;
  
  _DownloadTask({
    required this.url,
    required this.filePath,
    this.fileName,
    this.onProgress,
    this.onStatus,
    required this.completer,
  });
}

/// 通用的文件下载服务
/// 支持断点续传和并发下载（最多2个线程）
class FileDownloadService {
  late final Dio _dio;
  final ClientLoggerService _logger = ClientLoggerService();
  final DownloadDirectoryService _downloadDirService = DownloadDirectoryService();
  
  FileDownloadService() {
    // 配置 Dio 实例的超时设置
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30), // 连接超时30秒
      receiveTimeout: const Duration(minutes: 30), // 接收超时30分钟
      sendTimeout: const Duration(seconds: 30), // 发送超时30秒
      followRedirects: true, // 跟随重定向
      validateStatus: (status) => status != null && status < 500, // 允许部分内容(206)等状态码
    ));
  }
  
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
  /// [onStatus] 状态回调，用于通知UI当前操作状态
  /// 
  /// 返回下载文件的路径
  Future<String> downloadFile({
    required String url,
    String? fileName,
    Function(int received, int total)? onProgress,
    Function(String status)? onStatus,
  }) async {
    try {
      _logger.log('开始下载文件: $url', tag: 'DOWNLOAD');
      
      // 获取下载目录（使用DownloadDirectoryService）
      final downloadDir = await _downloadDirService.getDownloadDirectory();
      
      // 确定文件名
      String finalFileName = fileName ?? path.basename(url);
      if (finalFileName.isEmpty) {
        finalFileName = 'download_${DateTime.now().millisecondsSinceEpoch}';
      }
      
      final filePath = path.join(downloadDir, finalFileName);
      _logger.log('保存路径: $filePath', tag: 'DOWNLOAD');
      
      // 检查文件是否已存在（断点续传）
      onStatus?.call('正在检查已存在的文件...');
      int startByte = 0;
      final file = File(filePath);
      if (await file.exists()) {
        startByte = await file.length();
        _logger.log('发现已存在的文件，从字节 $startByte 继续下载', tag: 'DOWNLOAD');
        if (startByte > 0) {
          onStatus?.call('发现未完成的下载，准备断点续传...');
        }
      }
      
      // 创建下载任务
      final completer = Completer<String>();
      final task = _DownloadTask(
        url: url,
        filePath: filePath,
        fileName: fileName,
        onProgress: onProgress,
        onStatus: onStatus,
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
        task.onStatus?.call('正在恢复下载...');
      } else {
        task.onStatus?.call('正在连接服务器...');
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
        ),
        deleteOnError: false, // 保留部分下载的文件
      );
      
      // 验证文件是否存在
      if (await file.exists()) {
        final fileSize = await file.length();
        _logger.log('文件下载完成: ${task.filePath}, 大小: $fileSize 字节', tag: 'DOWNLOAD');
        
        // 如果文件大小异常小，可能是下载中断了
        if (fileSize < 1024 && task.downloadedBytes == 0) {
          throw Exception('下载的文件大小异常小（$fileSize 字节），可能下载失败');
        }
        
        task.completer.complete(task.filePath);
      } else {
        throw Exception('文件下载完成但文件不存在');
      }
    } on DioException catch (e, stackTrace) {
      // Dio 特定错误处理
      String errorMessage = '下载失败';
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = '连接超时，请检查网络连接';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = '接收超时，下载速度过慢或网络不稳定';
      } else if (e.type == DioExceptionType.sendTimeout) {
        errorMessage = '发送超时，请检查网络连接';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = '网络连接错误，请检查网络设置';
      } else if (e.type == DioExceptionType.badResponse) {
        errorMessage = '服务器响应错误: ${e.response?.statusCode}';
      } else if (e.type == DioExceptionType.cancel) {
        errorMessage = '下载已取消';
      } else {
        errorMessage = '下载失败: ${e.message ?? e.toString()}';
      }
      
      _logger.logError(errorMessage, error: e, stackTrace: stackTrace);
      task.completer.completeError(Exception(errorMessage));
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

}

