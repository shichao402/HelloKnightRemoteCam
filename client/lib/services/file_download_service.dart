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
  final DownloadDirectoryService _downloadDirService =
      DownloadDirectoryService();

  FileDownloadService() {
    // 配置 Dio 实例的超时设置
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30), // 连接超时30秒
      receiveTimeout: const Duration(minutes: 30), // 接收超时30分钟
      sendTimeout: const Duration(seconds: 30), // 发送超时30秒
      followRedirects: true, // 跟随重定向
      validateStatus: (status) =>
          status != null && status < 500, // 允许部分内容(206)等状态码
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
      // 判断下载来源
      String downloadSource = 'Unknown';
      if (url.contains('gitee.com')) {
        downloadSource = 'Gitee';
      } else if (url.contains('github.com')) {
        downloadSource = 'GitHub';
      }

      _logger.log('开始下载文件: $url', tag: 'DOWNLOAD');
      _logger.log('下载来源: $downloadSource', tag: 'DOWNLOAD');

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
        _logger.log('发现已存在的文件，大小: $startByte 字节', tag: 'DOWNLOAD');

        // 如果文件异常小（可能是错误页面），删除它重新下载
        if (startByte > 0 && startByte < 1024) {
          _logger.log('文件大小异常小($startByte 字节)，可能是错误页面，删除后重新下载',
              tag: 'DOWNLOAD');
          try {
            await file.delete();
            startByte = 0;
            _logger.log('已删除异常小的文件', tag: 'DOWNLOAD');
          } catch (e) {
            _logger.logError('删除异常文件失败', error: e);
          }
        }

        if (startByte > 0) {
          _logger.log('从字节 $startByte 继续下载（断点续传）', tag: 'DOWNLOAD');
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
        _logger.log('下载任务已加入等待队列，当前活跃数: ${_activeDownloads.length}',
            tag: 'DOWNLOAD');
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

      // 判断下载来源
      String downloadSource = 'Unknown';
      if (task.url.contains('gitee.com')) {
        downloadSource = 'Gitee';
      } else if (task.url.contains('github.com')) {
        downloadSource = 'GitHub';
      }

      _logger.log('=== 开始下载任务 ===', tag: 'DOWNLOAD');
      _logger.log('下载来源: $downloadSource', tag: 'DOWNLOAD');
      _logger.log('URL: ${task.url}', tag: 'DOWNLOAD');
      _logger.log('文件路径: ${task.filePath}', tag: 'DOWNLOAD');
      _logger.log('文件是否存在: $fileExists', tag: 'DOWNLOAD');
      _logger.log('已下载字节数: ${task.downloadedBytes}', tag: 'DOWNLOAD');

      // 先获取文件的完整大小（用于验证和日志）
      int? expectedTotalSize;
      try {
        _logger.log('发送 HEAD 请求获取文件大小...', tag: 'DOWNLOAD');
        _logger.log('HEAD 请求 URL: ${task.url}', tag: 'DOWNLOAD');
        final headResponse = await _dio.head(task.url);
        _logger.log('HEAD 响应状态码: ${headResponse.statusCode}', tag: 'DOWNLOAD');

        // 检查响应状态码
        if (headResponse.statusCode != null &&
            headResponse.statusCode! >= 400) {
          _logger.logError('HEAD 请求失败',
              error:
                  'HTTP ${headResponse.statusCode} - ${headResponse.statusMessage}');
          _logger.logError('URL可能不存在或无法访问', error: 'URL: ${task.url}');
          // 如果HEAD请求失败（特别是404），立即抛出异常以触发fallback机制
          // 这样可以避免下载错误页面（如HTML错误页面）
          throw DioException(
            requestOptions: RequestOptions(path: task.url),
            response: headResponse,
            type: DioExceptionType.badResponse,
            message: 'HEAD请求失败: HTTP ${headResponse.statusCode} - URL可能不存在',
          );
        }

        final contentLength = headResponse.headers.value('content-length');
        _logger.log('Content-Length 头值: $contentLength', tag: 'DOWNLOAD');

        if (contentLength != null) {
          expectedTotalSize = int.tryParse(contentLength);
          if (expectedTotalSize != null) {
            _logger.log('远程文件大小: $expectedTotalSize 字节', tag: 'DOWNLOAD');
          } else {
            _logger.log('无法解析 Content-Length: $contentLength', tag: 'DOWNLOAD');
          }
        } else {
          _logger.log('HEAD 响应中未找到 Content-Length 头', tag: 'DOWNLOAD');
          // 检查Content-Type，如果是HTML，可能是错误页面
          final contentType = headResponse.headers.value('content-type');
          if (contentType != null && contentType.contains('text/html')) {
            _logger.logError('HEAD 响应返回HTML页面，可能是错误页面或重定向',
                error: 'Content-Type: $contentType');
          }
        }
      } catch (e, stackTrace) {
        _logger.logError('获取远程文件大小失败', error: e, stackTrace: stackTrace);
        _logger.logError('URL: ${task.url}', error: e);
      }

      // 设置Range头支持断点续传
      final headers = <String, dynamic>{
        'Accept': '*/*',
      };
      if (fileExists && task.downloadedBytes > 0) {
        headers['Range'] = 'bytes=${task.downloadedBytes}-';
        _logger.log('使用断点续传，Range 头: ${headers['Range']}', tag: 'DOWNLOAD');
        task.onStatus?.call('正在恢复下载...');
      } else {
        _logger.log('全新下载，不使用 Range 头', tag: 'DOWNLOAD');
        task.onStatus?.call('正在连接服务器...');
      }

      // 用于跟踪实际下载的总大小
      // 注意：当使用断点续传时，Dio回调中的total是Range响应的Content-Length（剩余部分大小）
      // 而不是完整文件大小，所以不应该使用HEAD请求的完整大小
      bool isResumeDownload = fileExists && task.downloadedBytes > 0;
      int? actualTotalSize;
      int? lastReceived = null;
      int? lastTotal = null;
      int progressCallbackCount = 0;

      // 下载文件（Dio会自动处理断点续传）
      _logger.log('开始 Dio.download() 调用...', tag: 'DOWNLOAD');
      _logger.log('是否断点续传: $isResumeDownload', tag: 'DOWNLOAD');
      await _dio.download(
        task.url,
        task.filePath,
        onReceiveProgress: (received, total) {
          progressCallbackCount++;

          // 记录每次进度回调的详细信息
          if (progressCallbackCount == 1 ||
              received == total ||
              (lastReceived != null && (received - lastReceived!) > 1000000) ||
              (lastTotal != null && lastTotal != total)) {
            _logger.log(
                '进度回调 #$progressCallbackCount: received=$received, total=$total',
                tag: 'DOWNLOAD');
            _logger.log('  - downloadedBytes=${task.downloadedBytes}',
                tag: 'DOWNLOAD');
            _logger.log('  - expectedTotalSize=$expectedTotalSize',
                tag: 'DOWNLOAD');
          }

          lastReceived = received;
          lastTotal = total;

          // 对于断点续传，total 是Range响应的Content-Length（剩余部分大小）
          // 对于全新下载，total 是完整文件大小
          // 注意：不应该使用HEAD请求的expectedTotalSize，因为：
          // 1. 断点续传时，HEAD返回的是完整文件大小，而Range响应返回的是剩余部分大小
          // 2. 应该使用Dio回调中的total参数，这是实际响应的Content-Length
          if (task.downloadedBytes > 0) {
            // 断点续传：total是剩余部分大小，实际总大小 = 已下载 + total
            actualTotalSize = task.downloadedBytes + total;
            if (progressCallbackCount == 1 || received == total) {
              _logger.log('  - 断点续传: total=$total 是剩余部分大小', tag: 'DOWNLOAD');
              _logger.log(
                  '  - 计算的总大小: $actualTotalSize (${task.downloadedBytes} + $total)',
                  tag: 'DOWNLOAD');
              if (expectedTotalSize != null &&
                  actualTotalSize != expectedTotalSize) {
                _logger.log(
                    '  - 警告: HEAD返回的完整大小($expectedTotalSize)与计算的总大小($actualTotalSize)不一致',
                    tag: 'DOWNLOAD');
              }
            }
          } else {
            // 全新下载：total是完整文件大小
            actualTotalSize = total > 0 ? total : expectedTotalSize;
            if (progressCallbackCount == 1 || received == total) {
              if (expectedTotalSize != null &&
                  total > 0 &&
                  total != expectedTotalSize) {
                _logger.log(
                    '  - 警告: HEAD返回的大小($expectedTotalSize)与下载回调的total($total)不一致',
                    tag: 'DOWNLOAD');
              }
            }
          }

          // 计算实际接收的字节数（考虑断点续传）
          final actualReceived = task.downloadedBytes + received;
          final displayTotal = actualTotalSize ??
              (task.downloadedBytes + (total > 0 ? total : 0));

          if (progressCallbackCount == 1 || received == total) {
            _logger.log(
                '  - actualReceived=$actualReceived, displayTotal=$displayTotal',
                tag: 'DOWNLOAD');
            _logger.log('  - actualTotalSize=$actualTotalSize',
                tag: 'DOWNLOAD');
          }

          if (task.onProgress != null) {
            task.onProgress!(actualReceived, displayTotal);
          }

          if (displayTotal > 0) {
            final percent =
                (actualReceived / displayTotal * 100).toStringAsFixed(1);
            if (progressCallbackCount == 1 || received == total) {
              _logger.log('下载进度: $percent% ($actualReceived/$displayTotal)',
                  tag: 'DOWNLOAD');
            }
          }
        },
        options: Options(
          headers: headers,
        ),
        deleteOnError: false, // 保留部分下载的文件
      );

      _logger.log('Dio.download() 调用完成', tag: 'DOWNLOAD');
      _logger.log('总进度回调次数: $progressCallbackCount', tag: 'DOWNLOAD');
      _logger.log('最后 received: $lastReceived, lastTotal: $lastTotal',
          tag: 'DOWNLOAD');

      // 立即检查文件状态
      _logger.log('=== 下载完成，检查文件状态 ===', tag: 'DOWNLOAD');
      final fileExistsAfterDownload = await file.exists();
      _logger.log('文件是否存在: $fileExistsAfterDownload', tag: 'DOWNLOAD');

      if (fileExistsAfterDownload) {
        // 多次检查文件大小，观察是否有变化
        for (int i = 0; i < 5; i++) {
          final fileSize = await file.length();
          _logger.log('文件大小检查 #${i + 1}: $fileSize 字节', tag: 'DOWNLOAD');
          if (i < 4) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }

        final fileSize = await file.length();
        _logger.log('最终文件大小: $fileSize 字节', tag: 'DOWNLOAD');
        _logger.log('期望文件大小: $expectedTotalSize 字节', tag: 'DOWNLOAD');
        _logger.log('已下载字节数: ${task.downloadedBytes}', tag: 'DOWNLOAD');
        _logger.log('计算的总大小: $actualTotalSize', tag: 'DOWNLOAD');

        if (expectedTotalSize != null) {
          final sizeDiff = fileSize - expectedTotalSize;
          _logger.log('大小差异: $sizeDiff 字节', tag: 'DOWNLOAD');
        }

        // 如果文件大小异常小，可能是下载中断了
        if (fileSize < 1024 && task.downloadedBytes == 0) {
          _logger.logError('文件大小异常小', error: '$fileSize 字节');
          throw Exception('下载的文件大小异常小（$fileSize 字节），可能下载失败');
        }

        task.completer.complete(task.filePath);
      } else {
        _logger.logError('文件不存在', error: '下载完成但文件不存在');
        throw Exception('文件下载完成但文件不存在');
      }

      _logger.log('=== 下载任务完成 ===', tag: 'DOWNLOAD');
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
    if (_waitingQueue.isNotEmpty &&
        _activeDownloads.length < maxConcurrentDownloads) {
      final nextTask = _waitingQueue.removeAt(0);
      _startDownload(nextTask);
    }
  }
}
