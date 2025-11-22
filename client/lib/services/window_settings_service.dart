import 'package:shared_preferences/shared_preferences.dart';

/// 窗口设置服务：管理窗口大小和位置
class WindowSettingsService {
  static const String _keyWindowWidth = 'window_width';
  static const String _keyWindowHeight = 'window_height';
  static const String _keyWindowX = 'window_x';
  static const String _keyWindowY = 'window_y';
  
  // 默认窗口大小
  static const double defaultWidth = 1200.0;
  static const double defaultHeight = 800.0;
  
  // 最小窗口大小
  static const double minWidth = 800.0;
  static const double minHeight = 600.0;
  
  /// 保存窗口大小和位置
  Future<void> saveWindowBounds({
    required double width,
    required double height,
    required double x,
    required double y,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyWindowWidth, width);
      await prefs.setDouble(_keyWindowHeight, height);
      await prefs.setDouble(_keyWindowX, x);
      await prefs.setDouble(_keyWindowY, y);
    } catch (e) {
      // 忽略保存错误
    }
  }
  
  /// 获取保存的窗口大小和位置
  Future<Map<String, double>> getWindowBounds() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble(_keyWindowWidth) ?? defaultWidth;
    final height = prefs.getDouble(_keyWindowHeight) ?? defaultHeight;
    final x = prefs.getDouble(_keyWindowX);
    final y = prefs.getDouble(_keyWindowY);
    
    return {
      'width': width,
      'height': height,
      'x': x ?? 0,
      'y': y ?? 0,
    };
  }
  
  /// 检查是否有保存的窗口设置
  Future<bool> hasWindowBounds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyWindowWidth) && 
           prefs.containsKey(_keyWindowHeight);
  }
}

