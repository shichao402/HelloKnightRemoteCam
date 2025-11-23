import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

/// 下载设置服务：管理下载路径等设置
class DownloadSettingsService {
  static const String _keyDownloadPath = 'download_path';
  
  /// 获取下载路径（如果未设置，返回默认路径）
  Future<String> getDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(_keyDownloadPath);
    
    if (customPath != null && customPath.isNotEmpty) {
      return customPath;
    }
    
    // 默认路径：使用系统临时目录下的应用专属子目录
    // Downloads 目录用于存放用户下载的文件（与更新文件目录区分）
    final tempDir = await getTemporaryDirectory();
    return path.join(tempDir.path, 'com.example.remoteCamClient', 'Downloads');
  }
  
  /// 设置下载路径
  Future<void> setDownloadPath(String downloadPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadPath, downloadPath);
  }
  
  /// 重置为默认路径
  Future<String> resetToDefaultPath() async {
    final tempDir = await getTemporaryDirectory();
    final defaultPath = path.join(tempDir.path, 'com.example.remoteCamClient', 'Downloads');
    await setDownloadPath(defaultPath);
    return defaultPath;
  }
  
  /// 获取默认路径
  Future<String> getDefaultPath() async {
    final tempDir = await getTemporaryDirectory();
    return path.join(tempDir.path, 'com.example.remoteCamClient', 'Downloads');
  }
  
  /// 验证路径是否有效
  Future<bool> validatePath(String downloadPath) async {
    try {
      final dir = Directory(downloadPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}

