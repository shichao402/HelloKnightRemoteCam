import 'package:shared_preferences/shared_preferences.dart';

/// 方向偏好设置服务 - 保存客户端的锁定状态和旋转角度
class OrientationPreferencesService {
  static const String _keyOrientationLocked = 'orientation_locked';
  static const String _keyLockedRotationAngle = 'locked_rotation_angle';

  // 默认值
  static const bool defaultOrientationLocked = true;
  static const int defaultLockedRotationAngle = 0;

  /// 保存方向锁定状态
  Future<void> saveOrientationLocked(bool locked) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyOrientationLocked, locked);
    } catch (e) {
      print('保存方向锁定状态失败: $e');
    }
  }

  /// 保存锁定状态下的旋转角度
  Future<void> saveLockedRotationAngle(int angle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLockedRotationAngle, angle);
    } catch (e) {
      print('保存锁定旋转角度失败: $e');
    }
  }

  /// 获取方向锁定状态
  Future<bool> getOrientationLocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyOrientationLocked) ?? defaultOrientationLocked;
    } catch (e) {
      print('获取方向锁定状态失败: $e');
      return defaultOrientationLocked;
    }
  }

  /// 获取锁定状态下的旋转角度
  Future<int> getLockedRotationAngle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyLockedRotationAngle) ?? defaultLockedRotationAngle;
    } catch (e) {
      print('获取锁定旋转角度失败: $e');
      return defaultLockedRotationAngle;
    }
  }

  /// 获取所有方向偏好设置
  Future<Map<String, dynamic>> getAllPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'orientationLocked': prefs.getBool(_keyOrientationLocked) ?? defaultOrientationLocked,
        'lockedRotationAngle': prefs.getInt(_keyLockedRotationAngle) ?? defaultLockedRotationAngle,
      };
    } catch (e) {
      print('获取方向偏好设置失败: $e');
      return {
        'orientationLocked': defaultOrientationLocked,
        'lockedRotationAngle': defaultLockedRotationAngle,
      };
    }
  }

  /// 清除所有方向偏好设置
  Future<void> clearPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyOrientationLocked);
      await prefs.remove(_keyLockedRotationAngle);
    } catch (e) {
      print('清除方向偏好设置失败: $e');
    }
  }
}

