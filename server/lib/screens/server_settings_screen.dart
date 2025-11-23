import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';
import '../services/version_service.dart';
import 'package:shared/shared.dart';
import '../services/update_service.dart';

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
    
    // 注意：更新检查 URL 现在从 VERSION.yaml 读取，不再从设置中读取
    // 如果 URL 列表为空，尝试初始化（从 VERSION.yaml 读取）
    await _updateService.initializeUpdateUrls();
    
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
    // 确保 URL 列表已初始化（从 VERSION.yaml 读取）
    await _updateService.initializeUpdateUrls();

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
      builder: (dialogContext) => _UpdateDownloadDialog(
        updateService: _updateService,
        updateInfo: updateInfo,
        logger: _logger,
      ),
    );
  }

  void _showDownloadDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (dialogContext) => _UpdateDownloadDialog(
        updateService: _updateService,
        updateInfo: updateInfo,
        logger: _logger,
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
                child: const Text('取消', style: TextStyle(color: Colors.white)),
              ),
            ),
          if (_hasUnsavedChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton(
                onPressed: _saveAllSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                ),
                child: const Text('保存'),
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
            title: const Text('应用启动时自动启动HTTP服务器'),
            subtitle: const Text('启动应用时自动启动HTTP服务器'),
            value: _tempAutoStartServer,
            onChanged: _updateTempAutoStart,
          ),
          SwitchListTile(
            title: const Text('自动停止服务器 (电量优化)'),
            subtitle: Text(
              _tempAutoStopEnabled
                  ? '无客户端连接${_tempAutoStopMinutes == 0 ? '无限时间' : '$_tempAutoStopMinutes分钟后'}自动停止服务器'
                  : '禁用自动停止功能',
            ),
            value: _tempAutoStopEnabled,
            onChanged: _updateTempAutoStop,
          ),
          if (_tempAutoStopEnabled) ...[
            ListTile(
              title: Text('自动停止时间: ${_tempAutoStopMinutes == 0 ? '无限' : '$_tempAutoStopMinutes分钟'}'),
              subtitle: Slider(
                value: _tempAutoStopMinutes.toDouble(),
                min: 0,
                max: 60,
                divisions: 12,
                label: _tempAutoStopMinutes == 0 ? '无限' : '$_tempAutoStopMinutes分钟',
                onChanged: (value) => _updateTempAutoStopMinutes(value.toInt()),
              ),
            ),
          ],
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
              '关于',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            isThreeLine: _updateInfo != null,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('版本号'),
                if (_updateInfo != null) ...[
                  const SizedBox(height: 4),
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
                IconButton(
                  icon: _isCheckingUpdate
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _isCheckingUpdate ? null : _checkForUpdate,
                  tooltip: '检查更新',
                ),
                if (_updateInfo != null)
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () {
                      // 显示下载对话框
                      _showDownloadDialog(_updateInfo!);
                    },
                    tooltip: '下载新版本',
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

/// 更新下载对话框组件（支持下载进度显示）
class _UpdateDownloadDialog extends StatefulWidget {
  final UpdateService updateService;
  final UpdateInfo updateInfo;
  final LoggerService logger;

  const _UpdateDownloadDialog({
    required this.updateService,
    required this.updateInfo,
    required this.logger,
  });

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;

  /// 将技术性错误转换为友好的中文提示
  String _getFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // 404错误 - 文件不存在
    if (errorString.contains('404') || errorString.contains('not found')) {
      return '下载失败：更新文件不存在，请稍后重试或联系开发者';
    }
    
    // 网络连接错误
    if (errorString.contains('network') || 
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('socket') ||
        errorString.contains('failed host lookup')) {
      return '下载失败：网络连接异常，请检查网络设置后重试';
    }
    
    // 权限错误
    if (errorString.contains('permission') || 
        errorString.contains('denied') ||
        errorString.contains('unauthorized')) {
      return '下载失败：存储权限不足，请在设置中授予存储权限';
    }
    
    // 磁盘空间不足
    if (errorString.contains('space') || 
        errorString.contains('disk') ||
        errorString.contains('storage')) {
      return '下载失败：存储空间不足，请清理空间后重试';
    }
    
    // 文件路径相关错误
    if (errorString.contains('path') || 
        errorString.contains('file') ||
        errorString.contains('directory')) {
      return '下载失败：无法保存文件，请检查存储权限';
    }
    
    // 服务器错误
    if (errorString.contains('500') || 
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('server error')) {
      return '下载失败：服务器暂时不可用，请稍后重试';
    }
    
    // 其他错误 - 显示简化后的错误信息
    if (errorString.contains('dioexception')) {
      if (errorString.contains('bad response')) {
        return '下载失败：服务器响应异常，请稍后重试';
      }
      return '下载失败：网络请求异常，请检查网络连接';
    }
    
    // 默认错误提示
    return '下载失败：请检查网络连接后重试，如问题持续存在请联系开发者';
  }

  Future<void> _downloadAndOpen() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    try {
      widget.logger.log('开始下载更新文件', tag: 'UPDATE');
      
      final filePath = await widget.updateService.downloadUpdateFile(
        widget.updateInfo,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );

      if (filePath == null) {
        throw Exception('下载失败：文件路径为空');
      }

      widget.logger.log('下载完成，打开文件: $filePath', tag: 'UPDATE');
      
      // 关闭对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 打开文件
      final success = await widget.updateService.openDownloadedFile(filePath);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('下载完成，但无法打开文件'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      widget.logger.logError('下载更新文件失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = _getFriendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本: ${widget.updateInfo.version}'),
            const SizedBox(height: 8),
            if (widget.updateInfo.releaseNotes != null) ...[
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.updateInfo.releaseNotes!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '文件: ${widget.updateInfo.fileName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              const Text('正在下载...', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_totalBytes > 0)
                LinearProgressIndicator(
                  value: _downloadedBytes / _totalBytes,
                ),
              if (_totalBytes > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${(_downloadedBytes / _totalBytes * 100).toStringAsFixed(1)}% '
                  '(${(_downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB / '
                  '${(_totalBytes / 1024 / 1024).toStringAsFixed(2)} MB)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.logger.log('用户取消更新', tag: 'UPDATE');
            },
            child: const Text('取消'),
          ),
        ElevatedButton(
          onPressed: _isDownloading ? null : _downloadAndOpen,
          child: Text(_isDownloading ? '下载中...' : '立即下载'),
        ),
      ],
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

