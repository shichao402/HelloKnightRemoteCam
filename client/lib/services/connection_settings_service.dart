import 'package:shared_preferences/shared_preferences.dart';

class ConnectionSettingsService {
  static const String _hostKey = 'connection_host';
  static const String _portKey = 'connection_port';
  static const String _autoConnectKey = 'auto_connect_enabled';

  // 默认值
  static const String defaultHost = '192.168.50.205';
  static const int defaultPort = 8080;

  // 保存连接设置
  Future<void> saveConnectionSettings({
    required String host,
    required int port,
    bool autoConnect = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setInt(_portKey, port);
    await prefs.setBool(_autoConnectKey, autoConnect);
  }

  // 获取连接设置
  Future<Map<String, dynamic>> getConnectionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'host': prefs.getString(_hostKey) ?? defaultHost,
      'port': prefs.getInt(_portKey) ?? defaultPort,
      'autoConnect': prefs.getBool(_autoConnectKey) ?? true,
    };
  }

  // 检查是否有保存的连接信息
  Future<bool> hasSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_hostKey);
    return host != null && host.isNotEmpty;
  }

  // 清除连接设置
  Future<void> clearConnectionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hostKey);
    await prefs.remove(_portKey);
    await prefs.remove(_autoConnectKey);
  }
}

