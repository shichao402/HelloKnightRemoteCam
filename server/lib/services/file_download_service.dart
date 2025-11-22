import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'logger_service.dart';

/// 通用的文件下载服务
/// 可以在客户端和服务端复用
class FileDownloadService {
  final Dio _dio = Dio();
  final LoggerService _logger = LoggerService();

  /// 下载文件
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
      
      // 下载文件
      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (onProgress != null) {
            onProgress(received, total);
          }
          if (total > 0) {
            final percent = (received / total * 100).toStringAsFixed(1);
            _logger.log('下载进度: $percent% ($received/$total)', tag: 'DOWNLOAD');
          }
        },
        options: Options(
          headers: {
            'Accept': '*/*',
          },
        ),
      );
      
      // 验证文件是否存在
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        _logger.log('文件下载完成: $filePath, 大小: $fileSize 字节', tag: 'DOWNLOAD');
        return filePath;
      } else {
        throw Exception('文件下载完成但文件不存在');
      }
    } catch (e, stackTrace) {
      _logger.logError('下载文件失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 获取下载目录
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
    } else {
      // 其他平台：使用应用支持目录
      final appDir = await getApplicationSupportDirectory();
      return path.join(appDir.path, 'Downloads');
    }
  }
}

