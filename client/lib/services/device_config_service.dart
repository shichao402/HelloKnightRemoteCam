import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_settings.dart';
import 'logger_service.dart';

/// 设备配置服务 - 为每个设备保存相机配置
class DeviceConfigService {
  static const String _prefix = 'device_config_';
  final ClientLoggerService _logger = ClientLoggerService();
  
  /// 保存设备的相机配置
  Future<void> saveDeviceConfig(String deviceModel, CameraSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$deviceModel';
      final json = jsonEncode(settings.toJson());
      await prefs.setString(key, json);
    } catch (e) {
      _logger.logError('保存设备配置失败', error: e);
    }
  }
  
  /// 获取设备的相机配置
  Future<CameraSettings?> getDeviceConfig(String deviceModel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$deviceModel';
      final jsonStr = prefs.getString(key);
      
      if (jsonStr == null || jsonStr.isEmpty) {
        return null;
      }
      
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CameraSettings.fromJson(json);
    } catch (e) {
      _logger.logError('获取设备配置失败', error: e);
      return null;
    }
  }
  
  /// 检查是否有保存的设备配置
  Future<bool> hasDeviceConfig(String deviceModel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$deviceModel';
      return prefs.containsKey(key);
    } catch (e) {
      return false;
    }
  }
  
  /// 删除设备的配置
  Future<void> deleteDeviceConfig(String deviceModel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$deviceModel';
      await prefs.remove(key);
    } catch (e) {
      _logger.logError('删除设备配置失败', error: e);
    }
  }
  
  /// 获取所有已保存的设备型号列表
  Future<List<String>> getAllDeviceModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      return keys
          .where((key) => key.startsWith(_prefix))
          .map((key) => key.substring(_prefix.length))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

