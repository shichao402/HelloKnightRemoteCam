import 'package:flutter/services.dart';

/// MediaStore扫描服务：通知系统扫描新文件
class MediaScannerService {
  static const MethodChannel _channel = MethodChannel('com.example.remote_cam_server/media_scanner');

  /// 扫描文件，使其出现在相册中
  static Future<void> scanFile(String filePath) async {
    try {
      await _channel.invokeMethod('scanFile', {'filePath': filePath});
    } catch (e) {
      // 扫描失败不影响主流程，只记录错误
      print('MediaStore扫描失败: $e');
    }
  }

  /// 获取视频缩略图路径（如果存在）
  static Future<String?> getVideoThumbnail(String videoPath) async {
    try {
      final thumbnailPath = await _channel.invokeMethod<String>('getVideoThumbnail', {'videoPath': videoPath});
      return thumbnailPath;
    } catch (e) {
      return null;
    }
  }

  /// 获取缩略图路径（支持照片和视频）
  static Future<String?> getThumbnail(String filePath, bool isVideo) async {
    try {
      if (isVideo) {
        return await getVideoThumbnail(filePath);
      } else {
        // 照片缩略图
        final thumbnailPath = await _channel.invokeMethod<String>('getImageThumbnail', {'imagePath': filePath});
        return thumbnailPath;
      }
    } catch (e) {
      return null;
    }
  }
}

