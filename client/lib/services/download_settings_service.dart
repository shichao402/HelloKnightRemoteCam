import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

/// 下载设置服务：管理下载路径
/// 下载目录作为临时缓存目录，固定在媒体库目录旁边
class DownloadSettingsService {
  String? _cachedDownloadPath;
  
  /// 获取下载路径（固定在媒体库目录旁边的 downloads 文件夹）
  /// 目录结构：
  /// ~/Documents/HelloKnightRemoteCam/
  ///   ├── media/        # 媒体库目录（按日期组织）
  ///   └── downloads/    # 下载临时目录
  Future<String> getDownloadPath() async {
    if (_cachedDownloadPath != null) {
      return _cachedDownloadPath!;
    }
    
    final appDir = await getApplicationDocumentsDirectory();
    final downloadPath = path.join(appDir.path, 'HelloKnightRemoteCam', 'downloads');
    
    // 确保目录存在
    await Directory(downloadPath).create(recursive: true);
    
    _cachedDownloadPath = downloadPath;
    return downloadPath;
  }
  
  /// 清除缓存（用于测试或重新初始化）
  void clearCache() {
    _cachedDownloadPath = null;
  }
  
  /// 验证路径是否有效（保留用于兼容性）
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

