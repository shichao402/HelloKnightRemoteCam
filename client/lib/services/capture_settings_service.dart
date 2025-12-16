import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// 拍摄来源类型
enum CaptureSource {
  /// 本机摄像头
  localCamera,
  /// 远端相机（手机）
  remoteCamera,
}

/// 拍摄设置服务
/// 
/// 管理拍摄来源配置
class CaptureSettingsService {
  static const String _captureSourceKey = 'capture_source';

  /// 获取拍摄来源
  /// 
  /// 默认：
  /// - 移动端（Android/iOS）：本机摄像头
  /// - 桌面端：远端相机
  Future<CaptureSource> getCaptureSource() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_captureSourceKey);
    
    if (value == null) {
      // 默认值：移动端用本机，桌面端用远端
      return _getDefaultCaptureSource();
    }
    
    return CaptureSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => _getDefaultCaptureSource(),
    );
  }

  /// 设置拍摄来源
  Future<void> setCaptureSource(CaptureSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_captureSourceKey, source.name);
  }

  /// 获取默认拍摄来源
  CaptureSource _getDefaultCaptureSource() {
    if (Platform.isAndroid || Platform.isIOS) {
      return CaptureSource.localCamera;
    }
    return CaptureSource.remoteCamera;
  }

  /// 检查本机摄像头是否可用
  bool isLocalCameraSupported() {
    return Platform.isAndroid || Platform.isIOS;
  }
}
