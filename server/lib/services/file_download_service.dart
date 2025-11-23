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
      
      // 检查文件是否已存在
      final existingFile = File(filePath);
      if (await existingFile.exists()) {
        final existingSize = await existingFile.length();
        _logger.log('文件已存在: $filePath, 大小: $existingSize 字节', tag: 'DOWNLOAD');
        
        // 尝试获取远程文件大小（如果可能）
        try {
          final headResponse = await _dio.head(url);
          final contentLength = headResponse.headers.value('content-length');
          if (contentLength != null) {
            final remoteSize = int.tryParse(contentLength);
            if (remoteSize != null && existingSize == remoteSize) {
              _logger.log('文件已存在且大小匹配，跳过下载', tag: 'DOWNLOAD');
              // 调用进度回调，表示已完成
              if (onProgress != null) {
                onProgress(existingSize, existingSize);
              }
              return filePath;
            } else if (remoteSize != null && existingSize != remoteSize) {
              _logger.log('文件已存在但大小不匹配（本地: $existingSize, 远程: $remoteSize），重新下载', tag: 'DOWNLOAD');
              // 删除不完整的文件
              await existingFile.delete();
            }
          }
        } catch (e) {
          // 如果无法获取远程文件大小，继续下载（会覆盖现有文件）
          _logger.log('无法获取远程文件大小，将重新下载: $e', tag: 'DOWNLOAD');
        }
      }
      
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
      final downloadedFile = File(filePath);
      if (await downloadedFile.exists()) {
        final fileSize = await downloadedFile.length();
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
  /// 使用应用专属子目录，避免与其他应用冲突
  Future<String> _getDownloadDirectory() async {
    // 使用系统临时目录作为基础目录
    final tempDir = await getTemporaryDirectory();
    // 创建应用专属子目录：com.firoyang.helloknightrcc_server
    // Updates 目录用于存放更新文件
    final downloadDir = path.join(tempDir.path, 'com.firoyang.helloknightrcc_server', 'Updates');
    // 确保目录存在
    await Directory(downloadDir).create(recursive: true);
    return downloadDir;
  }
}


