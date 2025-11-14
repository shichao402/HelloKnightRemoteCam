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
  
  final LoggerService _logger = LoggerService();
  bool _autoStartServer = false;
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

// 静态方法：获取自动启动设置
class ServerSettings {
  static Future<bool> getAutoStart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_start_server') ?? false;
  }
}

