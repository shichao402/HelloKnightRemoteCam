import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'update_service.dart';

/// 更新设置服务：管理更新检查URL等设置（服务端）
class UpdateSettingsService {
  static const String _keyUpdateCheckUrl = 'update_check_url';
  static const String _keyUpdateInfo = 'update_info';
  static const String _keyLastUpdateCheck = 'last_update_check';
  
  // 默认更新检查URL（可以从环境变量或配置中读取）
  static const String defaultUpdateCheckUrl = '';
  
  /// 获取更新检查URL
  Future<String> getUpdateCheckUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUpdateCheckUrl) ?? defaultUpdateCheckUrl;
  }
  
  /// 设置更新检查URL
  Future<void> setUpdateCheckUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUpdateCheckUrl, url);
  }
  
  /// 检查是否已设置更新检查URL
  Future<bool> hasUpdateCheckUrl() async {
    final url = await getUpdateCheckUrl();
    return url.isNotEmpty;
  }
  
  /// 保存更新信息
  Future<void> saveUpdateInfo(UpdateInfo? updateInfo) async {
    final prefs = await SharedPreferences.getInstance();
    if (updateInfo == null) {
      await prefs.remove(_keyUpdateInfo);
    } else {
      final json = jsonEncode({
        'version': updateInfo.version,
        'versionNumber': updateInfo.versionNumber,
        'downloadUrl': updateInfo.downloadUrl,
        'fileName': updateInfo.fileName,
        'fileType': updateInfo.fileType,
        'platform': updateInfo.platform,
        'releaseNotes': updateInfo.releaseNotes,
      });
      await prefs.setString(_keyUpdateInfo, json);
    }
    await prefs.setInt(_keyLastUpdateCheck, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// 获取保存的更新信息
  Future<UpdateInfo?> getUpdateInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyUpdateInfo);
    if (jsonStr == null) return null;
    
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return UpdateInfo.fromJson(json);
    } catch (e) {
      return null;
    }
  }
  
  /// 检查是否有可用的更新信息
  Future<bool> hasUpdate() async {
    final updateInfo = await getUpdateInfo();
    return updateInfo != null;
  }
  
  /// 获取最后检查更新的时间
  Future<DateTime?> getLastUpdateCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyLastUpdateCheck);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
}

