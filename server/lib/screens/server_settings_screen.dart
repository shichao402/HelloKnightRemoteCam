import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({Key? key}) : super(key: key);

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  static const String _autoStartKey = 'auto_start_server';
  static const String _autoStopEnabledKey = 'auto_stop_enabled';
  static const String _autoStopSecondsKey = 'auto_stop_seconds'; // 改为秒为单位存储
  
  final LoggerService _logger = LoggerService();
  bool _autoStartServer = false;
  bool _autoStopEnabled = false;
  int _autoStopMinutes = 15; // UI显示用分钟，内部转换为秒存储
  bool _debugMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoStartServer = prefs.getBool(_autoStartKey) ?? false;
      _autoStopEnabled = prefs.getBool(_autoStopEnabledKey) ?? false;
      // 从秒转换为分钟显示
      // 默认20秒，显示为1分钟（向上取整）
      // 0秒表示无限时间，显示为0分钟
      final seconds = prefs.getInt(_autoStopSecondsKey) ?? 20;
      _autoStopMinutes = seconds == 0 ? 0 : (seconds / 60).ceil(); // 向上取整到分钟
      _debugMode = _logger.debugEnabled;
      _isLoading = false;
    });
  }

  Future<void> _saveAutoStart(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartKey, value);
    setState(() {
      _autoStartServer = value;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '已启用自动启动服务器' : '已禁用自动启动服务器'),
        ),
      );
    }
  }

  Future<void> _saveAutoStop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStopEnabledKey, value);
    setState(() {
      _autoStopEnabled = value;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value 
            ? (_autoStopMinutes == 0 
                ? '已启用自动停止服务器\n但设置为无限时间（不会自动停止）'
                : '已启用自动停止服务器\n无客户端连接${_autoStopMinutes}分钟后将自动停止')
            : '已禁用自动停止服务器'),
        ),
      );
    }
  }

  Future<void> _saveAutoStopMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    // UI显示分钟，但存储时转换为秒
    // 0分钟表示无限时间，保存为0秒
    final seconds = minutes == 0 ? 0 : minutes * 60;
    await prefs.setInt(_autoStopSecondsKey, seconds);
    setState(() {
      _autoStopMinutes = minutes;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(minutes == 0 
            ? '自动停止时间已设置为无限（不自动停止）'
            : '自动停止时间已设置为${minutes}分钟（${seconds}秒）'),
        ),
      );
    }
  }

  Future<void> _saveDebugMode(bool value) async {
    await _logger.setDebugMode(value);
    setState(() {
      _debugMode = value;
    });
    
    if (value) {
      await _logger.cleanOldLogs();
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '调试模式已启用\n日志将保存到文件' : '调试模式已禁用'),
        ),
      );
    }
  }

  Future<void> _viewLogFiles() async {
    final files = await _logger.getLogFiles();
    
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无日志文件')),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('日志文件'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final size = file.lengthSync();
                final modified = file.lastModifiedSync();
                
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.description),
                  title: Text(
                    file.path.split('/').last,
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    '${(size / 1024).toStringAsFixed(1)} KB - ${modified.toString().substring(0, 16)}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                for (var file in files) {
                  await file.delete();
                }
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('所有日志文件已删除')),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('全部删除'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '服务器设置',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('启动后自动启动服务器'),
            subtitle: const Text('应用启动时自动启动HTTP服务器'),
            value: _autoStartServer,
            onChanged: _saveAutoStart,
          ),
          SwitchListTile(
            title: const Text('自动停止服务器（电量优化）'),
            subtitle: Text(_autoStopEnabled 
              ? (_autoStopMinutes == 0 
                  ? '已启用自动停止，但设置为无限时间（不会自动停止）'
                  : '无客户端连接${_autoStopMinutes}分钟后自动停止服务器')
              : '无客户端连接时自动停止服务器以节省电量'),
            value: _autoStopEnabled,
            onChanged: _saveAutoStop,
          ),
          if (_autoStopEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _autoStopMinutes == 0 
                      ? '自动停止时间: 无限（不自动停止）'
                      : '自动停止时间: ${_autoStopMinutes}分钟',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Slider(
                    value: _autoStopMinutes.toDouble(),
                    min: 0,
                    max: 60,
                    divisions: 60,
                    label: _autoStopMinutes == 0 ? '无限' : '${_autoStopMinutes}分钟',
                    onChanged: (value) {
                      _saveAutoStopMinutes(value.toInt());
                    },
                  ),
                ],
              ),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '调试设置',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('启用调试模式'),
            subtitle: const Text('将详细日志保存到文件'),
            value: _debugMode,
            onChanged: _saveDebugMode,
          ),
          if (_debugMode)
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('查看日志文件'),
              subtitle: const Text('查看和管理保存的日志文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _viewLogFiles,
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '提示',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '• 自动启动服务器功能需要预先设置用户名和密码\n'
              '• 调试模式会自动清理10个以上的旧日志文件\n'
              '• 日志文件可能包含敏感信息，请谨慎分享',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 静态方法：获取服务器设置
class ServerSettings {
  static const String _autoStartKey = 'auto_start_server';
  static const String _autoStopEnabledKey = 'auto_stop_enabled';
  static const String _autoStopSecondsKey = 'auto_stop_seconds'; // 改为秒为单位存储
  
  static Future<bool> getAutoStart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoStartKey) ?? false;
  }
  
  static Future<bool> getAutoStopEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoStopEnabledKey) ?? false;
  }
  
  // 返回秒数（存储单位）
  static Future<int> getAutoStopSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoStopSecondsKey) ?? 20; // 默认20秒
  }
  
  // 兼容旧方法名（已废弃，保留用于迁移）
  @Deprecated('使用 getAutoStopSeconds() 代替')
  static Future<int> getAutoStopMinutes() async {
    final seconds = await getAutoStopSeconds();
    return (seconds / 60).ceil(); // 转换为分钟
  }
}

