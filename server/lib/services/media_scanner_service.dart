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
}

