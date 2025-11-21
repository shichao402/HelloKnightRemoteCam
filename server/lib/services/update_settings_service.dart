import 'package:shared_preferences/shared_preferences.dart';

/// 更新设置服务：管理更新检查URL等设置（服务端）
class UpdateSettingsService {
  static const String _keyUpdateCheckUrl = 'update_check_url';
  
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
}

