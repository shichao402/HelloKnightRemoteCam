import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/logger_service.dart';
import '../services/version_service.dart';
import '../services/capture_settings_service.dart';
import '../services/connection_settings_service.dart';
import 'package:shared/shared.dart';
import '../services/update_service.dart';
import '../core/media/services/media_library_service.dart';

class ClientSettingsScreen extends StatefulWidget {
  /// 拍摄来源变更回调
  final VoidCallback? onCaptureSourceChanged;
  /// 更新状态变更回调
  final VoidCallback? onUpdateStatusChanged;

  const ClientSettingsScreen({
    Key? key,
    this.onCaptureSourceChanged,
    this.onUpdateStatusChanged,
  }) : super(key: key);

  @override
  State<ClientSettingsScreen> createState() => _ClientSettingsScreenState();
}

class _ClientSettingsScreenState extends State<ClientSettingsScreen> {
  final ClientLoggerService _logger = ClientLoggerService();
  final VersionService _versionService = VersionService();
  final UpdateService _updateService = UpdateService();
  final CaptureSettingsService _captureSettings = CaptureSettingsService();
  final ConnectionSettingsService _connectionSettings = ConnectionSettingsService();
  
  bool _debugMode = false;
  bool _isLoading = true;
  String _version = '加载中...';
  bool _isCheckingUpdate = false;
  UpdateInfo? _updateInfo;
  CaptureSource _captureSource = CaptureSource.remoteCamera;
  String _serverHost = '';
  int _serverPort = 8080;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final version = await _versionService.getVersion();
    final captureSource = await _captureSettings.getCaptureSource();
    final connectionSettings = await _connectionSettings.getConnectionSettings();

    // 注意：更新检查 URL 现在从 VERSION.yaml 读取，不再从设置中读取
    // 如果 URL 列表为空，尝试初始化（从 VERSION.yaml 读取）
    await _updateService.initializeUpdateUrls();

    // 检查是否有保存的更新信息
    final updateInfo = await _updateService.getSavedUpdateInfo();

    setState(() {
      _debugMode = _logger.debugEnabled;
      _version = version;
      _updateInfo = updateInfo;
      _captureSource = captureSource;
      _serverHost = connectionSettings['host'] as String;
      _serverPort = connectionSettings['port'] as int;
      _isLoading = false;
    });
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
                    '${_formatFileSize(size)} • ${_formatDate(modified)}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copyLogPath(file.path),
                        tooltip: '复制路径',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () => _deleteLogFile(file),
                        tooltip: '删除',
                      ),
                    ],
                  ),
                  onTap: () => _viewLogContent(file),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            TextButton(
              onPressed: () => _clearAllLogs(),
              child: const Text('清空所有日志', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _viewLogContent(File file) async {
    try {
      final content = await file.readAsString();

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(file.path.split('/').last),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制到剪贴板')),
                  );
                },
                child: const Text('复制全部'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取日志失败: $e')),
        );
      }
    }
  }

  Future<void> _copyLogPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('路径已复制到剪贴板')),
      );
    }
  }

  Future<void> _deleteLogFile(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日志文件'),
        content: Text('确定要删除 ${file.path.split('/').last} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await file.delete();
        if (mounted) {
          Navigator.of(context).pop(); // 关闭日志文件列表对话框
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('日志文件已删除')),
          );
          _viewLogFiles(); // 刷新列表
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _clearAllLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有日志'),
        content: const Text('确定要删除所有日志文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _logger.cleanAllLogs();
        if (mounted) {
          Navigator.of(context).pop(); // 关闭日志文件列表对话框
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所有日志文件已清空')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清空失败: $e')),
          );
        }
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
    _updateService.showUpdateDialog(context, updateInfo);
  }

  /// 显示拍摄来源选择对话框
  void _showCaptureSourceDialog() {
    final isLocalSupported = _captureSettings.isLocalCameraSupported();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择拍摄来源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<CaptureSource>(
              title: const Text('本机摄像头'),
              subtitle: Text(isLocalSupported 
                  ? '使用当前设备的摄像头' 
                  : '桌面平台暂不支持'),
              value: CaptureSource.localCamera,
              groupValue: _captureSource,
              onChanged: isLocalSupported 
                  ? (value) => _setCaptureSource(value!, context)
                  : null,
            ),
            RadioListTile<CaptureSource>(
              title: const Text('远端相机'),
              subtitle: const Text('连接手机作为远程相机'),
              value: CaptureSource.remoteCamera,
              groupValue: _captureSource,
              onChanged: (value) => _setCaptureSource(value!, context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _setCaptureSource(CaptureSource source, BuildContext dialogContext) async {
    await _captureSettings.setCaptureSource(source);
    setState(() {
      _captureSource = source;
    });
    widget.onCaptureSourceChanged?.call();
    if (mounted) {
      Navigator.pop(dialogContext);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('拍摄来源已设置为: ${source == CaptureSource.localCamera ? "本机摄像头" : "远端相机"}'),
        ),
      );
    }
  }

  /// 显示服务器设置对话框
  void _showServerSettingsDialog() {
    final hostController = TextEditingController(text: _serverHost);
    final portController = TextEditingController(text: _serverPort.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('远端服务器设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: '服务器IP地址',
                hintText: '例如: 192.168.1.100',
                prefixIcon: Icon(Icons.dns),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: '端口',
                prefixIcon: Icon(Icons.settings_ethernet),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final host = hostController.text.trim();
              final port = int.tryParse(portController.text) ?? 8080;
              
              if (host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入服务器地址')),
                );
                return;
              }
              
              await _connectionSettings.saveConnectionSettings(
                host: host,
                port: port,
                autoConnect: true,
              );
              
              setState(() {
                _serverHost = host;
                _serverPort = port;
              });
              
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('服务器设置已保存: $host:$port')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 重建媒体库数据库
  Future<void> _rebuildMediaLibrary() async {
    // 先确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重建媒体库'),
        content: const Text(
          '此操作将清空媒体库数据库，并重新扫描媒体库目录中的所有文件。\n\n'
          '注意：\n'
          '• 文件本身不会被删除\n'
          '• 星标、标签等信息会丢失\n'
          '• 与服务器的关联需要重新建立\n\n'
          '确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('重建'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 显示进度对话框
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RebuildProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // 拍摄设置
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '拍摄设置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('拍摄来源'),
                  subtitle: Text(_captureSource == CaptureSource.localCamera 
                      ? '本机摄像头' 
                      : '远端相机（手机）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showCaptureSourceDialog,
                ),
                if (_captureSource == CaptureSource.remoteCamera) ...[
                  ListTile(
                    leading: const Icon(Icons.dns),
                    title: const Text('远端服务器'),
                    subtitle: Text('$_serverHost:$_serverPort'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showServerSettingsDialog,
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
                // 媒体库设置
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '媒体库',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('重建媒体库'),
                  subtitle: const Text('清空数据库并重新扫描本地文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _rebuildMediaLibrary,
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
                    '• 启用调试模式后，所有操作和API调用都会记录到日志文件\n'
                    '• 日志文件保存在: ~/Library/Logs/HelloKnightRCC/\n'
                    '• 系统会自动清理旧日志，保留最近10个文件\n'
                    '• 单个日志文件最大10MB，总大小最大50MB',
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
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('版本号'),
                      if (_updateInfo != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.system_update,
                                  size: 14, color: Colors.white),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        onPressed: _isCheckingUpdate ? null : _checkForUpdate,
                        tooltip: '检查更新',
                      ),
                      if (_updateInfo != null)
                        IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () {
                            _showUpdateDialog(_updateInfo!);
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

/// 重建进度对话框
class _RebuildProgressDialog extends StatefulWidget {
  @override
  State<_RebuildProgressDialog> createState() => _RebuildProgressDialogState();
}

class _RebuildProgressDialogState extends State<_RebuildProgressDialog> {
  bool _isRebuilding = true;
  int _current = 0;
  int _total = 0;
  String _currentFile = '';
  RebuildResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startRebuild();
  }

  Future<void> _startRebuild() async {
    try {
      final libraryService = MediaLibraryService.instance;
      await libraryService.init();
      
      final result = await libraryService.rebuildDatabase(
        onProgress: (current, total, fileName) {
          if (mounted) {
            setState(() {
              _current = current;
              _total = total;
              _currentFile = fileName;
            });
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _isRebuilding = false;
          _result = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRebuilding = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isRebuilding ? '正在重建媒体库...' : '重建完成'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isRebuilding) ...[
            LinearProgressIndicator(
              value: _total > 0 ? _current / _total : null,
            ),
            const SizedBox(height: 16),
            Text('进度: $_current / $_total'),
            const SizedBox(height: 8),
            Text(
              '当前文件: $_currentFile',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (_error != null) ...[
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('重建失败: $_error'),
          ] else if (_result != null) ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text('扫描文件: ${_result!.scannedCount}'),
            Text('成功导入: ${_result!.importedCount}'),
            if (_result!.failedCount > 0)
              Text(
                '导入失败: ${_result!.failedCount}',
                style: const TextStyle(color: Colors.orange),
              ),
          ],
        ],
      ),
      actions: [
        if (!_isRebuilding)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
      ],
    );
  }
}
