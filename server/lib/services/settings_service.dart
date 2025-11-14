import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_settings.dart';

class SettingsService {
  static const String _settingsKey = 'camera_settings';

  // 保存设置
  Future<void> saveSettings(CameraSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(settings.toJson());
    await prefs.setString(_settingsKey, jsonString);
  }

  // 加载设置
  Future<CameraSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_settingsKey);
    
    if (jsonString == null) {
      // 返回默认设置
      return const CameraSettings();
    }

    try {
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      return CameraSettings.fromJson(jsonMap);
    } catch (e) {
      print('加载设置失败: $e');
      return const CameraSettings();
    }
  }

  // 重置为默认设置
  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_settingsKey);
  }
}

