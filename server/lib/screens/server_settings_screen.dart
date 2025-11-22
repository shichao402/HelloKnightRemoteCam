import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';
import '../services/version_service.dart';
import '../services/update_service.dart';
import '../services/update_settings_service.dart';

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
  final VersionService _versionService = VersionService();
  final UpdateService _updateService = UpdateService();
  final UpdateSettingsService _updateSettings = UpdateSettingsService();
  bool _autoStartServer = false;
  bool _autoStopEnabled = false;
  int _autoStopMinutes = 15; // UI显示用分钟，内部转换为秒存储
  bool _debugMode = false;
  bool _isLoading = true;
  String _version = '加载中...';
  bool _isCheckingUpdate = false;
  UpdateInfo? _updateInfo;
  
  // 临时状态（未保存的修改）
  bool _tempAutoStartServer = false;
  bool _tempAutoStopEnabled = false;
  int _tempAutoStopMinutes = 15;
  bool _tempDebugMode = false;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final version = await _versionService.getVersion();
    final updateCheckUrl = await _updateSettings.getUpdateCheckUrl();
    
    // 设置更新检查URL
    if (updateCheckUrl.isNotEmpty) {
      _updateService.setUpdateCheckUrl(updateCheckUrl);
    }
    
    // 检查是否有保存的更新信息
    final updateInfo = await _updateService.getSavedUpdateInfo();
    
    setState(() {
      _autoStartServer = prefs.getBool(_autoStartKey) ?? false;
      _autoStopEnabled = prefs.getBool(_autoStopEnabledKey) ?? false;
      // 从秒转换为分钟显示
      // 默认20秒，显示为1分钟（向上取整）
      // 0秒表示无限时间，显示为0分钟
      final seconds = prefs.getInt(_autoStopSecondsKey) ?? 20;
      _autoStopMinutes = seconds == 0 ? 0 : (seconds / 60).ceil(); // 向上取整到分钟
      _debugMode = _logger.debugEnabled;
      _version = version;
      _updateInfo = updateInfo;
      
      // 同步临时状态
      _tempAutoStartServer = _autoStartServer;
      _tempAutoStopEnabled = _autoStopEnabled;
      _tempAutoStopMinutes = _autoStopMinutes;
      _tempDebugMode = _debugMode;
      _hasUnsavedChanges = false;
      
      _isLoading = false;
    });
  }

  // 更新临时状态（不保存）
  void _updateTempAutoStart(bool value) {
    setState(() {
      _tempAutoStartServer = value;
      _hasUnsavedChanges = _hasChanges();
    });
  }

  void _updateTempAutoStop(bool value) {
    setState(() {
      _tempAutoStopEnabled = value;
      _hasUnsavedChanges = _hasChanges();
    });
  }

  void _updateTempAutoStopMinutes(int minutes) {
    setState(() {
      _tempAutoStopMinutes = minutes;
      _hasUnsavedChanges = _hasChanges();
    });
  }

  void _updateTempDebugMode(bool value) {
    setState(() {
      _tempDebugMode = value;
      _hasUnsavedChanges = _hasChanges();
    });
  }

  // 检查是否有未保存的更改
  bool _hasChanges() {
    return _tempAutoStartServer != _autoStartServer ||
           _tempAutoStopEnabled != _autoStopEnabled ||
           _tempAutoStopMinutes != _autoStopMinutes ||
           _tempDebugMode != _debugMode;
  }

  // 保存所有设置
  Future<void> _saveAllSettings() async {
    // 如果没有未保存的更改，直接返回
    if (!_hasUnsavedChanges) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有需要保存的更改'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    
    // 保存自动启动设置
    await prefs.setBool(_autoStartKey, _tempAutoStartServer);
    
    // 保存自动停止设置
    await prefs.setBool(_autoStopEnabledKey, _tempAutoStopEnabled);
    final seconds = _tempAutoStopMinutes == 0 ? 0 : _tempAutoStopMinutes * 60;
    await prefs.setInt(_autoStopSecondsKey, seconds);
    
    // 保存调试模式
    await _logger.setDebugMode(_tempDebugMode);
    if (_tempDebugMode) {
      await _logger.cleanOldLogs();
    }
    
    // 更新实际状态
    setState(() {
      _autoStartServer = _tempAutoStartServer;
      _autoStopEnabled = _tempAutoStopEnabled;
      _autoStopMinutes = _tempAutoStopMinutes;
      _debugMode = _tempDebugMode;
      _hasUnsavedChanges = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // 取消更改，恢复原始设置
  void _cancelChanges() {
    setState(() {
      _tempAutoStartServer = _autoStartServer;
      _tempAutoStopEnabled = _autoStopEnabled;
      _tempAutoStopMinutes = _autoStopMinutes;
      _tempDebugMode = _debugMode;
      _hasUnsavedChanges = false;
    });
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

  Future<void> _checkForUpdate() async {
    // 检查是否设置了更新检查URL
    final updateCheckUrl = await _updateSettings.getUpdateCheckUrl();
    if (updateCheckUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('更新检查URL未设置，请在配置中设置'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      // 设置界面手动检查更新时，始终从网络检查
      final result = await _updateService.checkForUpdate(avoidCache: true);

      if (!mounted) return;

      setState(() {
        _isCheckingUpdate = false;
      });

      if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: ${result.error}'),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      if (result.hasUpdate && result.updateInfo != null) {
        setState(() {
          _updateInfo = result.updateInfo;
        });
        // 显示更新对话框
        _showUpdateDialog(result.updateInfo!);
      } else {
        setState(() {
          _updateInfo = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前已是最新版本'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本: ${updateInfo.version}'),
            const SizedBox(height: 8),
            if (updateInfo.releaseNotes != null) ...[
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                updateInfo.releaseNotes!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '文件: ${updateInfo.fileName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await _updateService.openDownloadUrl(updateInfo.downloadUrl);
              if (mounted && !success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('无法打开下载链接'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
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
        actions: [
          if (_hasUnsavedChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _cancelChanges,
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _saveAllSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: _hasUnsavedChanges ? Colors.blue : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(
                Icons.save,
                size: 18,
              ),
              label: const Text(
                '保存',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
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
            value: _tempAutoStartServer,
            onChanged: _updateTempAutoStart,
          ),
          SwitchListTile(
            title: const Text('自动停止服务器（电量优化）'),
            subtitle: Text(_tempAutoStopEnabled 
              ? (_tempAutoStopMinutes == 0 
                  ? '已启用自动停止，但设置为无限时间（不会自动停止）'
                  : '无客户端连接${_tempAutoStopMinutes}分钟后自动停止服务器')
              : '无客户端连接时自动停止服务器以节省电量'),
            value: _tempAutoStopEnabled,
            onChanged: _updateTempAutoStop,
          ),
          if (_tempAutoStopEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tempAutoStopMinutes == 0 
                      ? '自动停止时间: 无限（不自动停止）'
                      : '自动停止时间: ${_tempAutoStopMinutes}分钟',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Slider(
                    value: _tempAutoStopMinutes.toDouble(),
                    min: 0,
                    max: 60,
                    divisions: 60,
                    label: _tempAutoStopMinutes == 0 ? '无限' : '${_tempAutoStopMinutes}分钟',
                    onChanged: (value) {
                      _updateTempAutoStopMinutes(value.toInt());
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
            value: _tempDebugMode,
            onChanged: _updateTempDebugMode,
          ),
          if (_tempDebugMode)
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
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '更新',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('检查更新'),
            subtitle: const Text('检查是否有新版本可用'),
            trailing: _isCheckingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isCheckingUpdate ? null : _checkForUpdate,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '关于',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Row(
              children: [
                const Text('版本号'),
                if (_updateInfo != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.system_update, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '新版本 ${_updateInfo!.version}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              _version,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_updateInfo != null)
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () async {
                      final success = await _updateService.openDownloadUrl(_updateInfo!.downloadUrl);
                      if (mounted && !success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('无法打开下载链接'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                    tooltip: '下载新版本',
                  ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _version));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('版本号已复制到剪贴板')),
                      );
                    }
                  },
                  tooltip: '复制版本号',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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

