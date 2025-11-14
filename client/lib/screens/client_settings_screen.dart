import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/logger_service.dart';
import '../services/download_settings_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

class ClientSettingsScreen extends StatefulWidget {
  const ClientSettingsScreen({Key? key}) : super(key: key);

  @override
  State<ClientSettingsScreen> createState() => _ClientSettingsScreenState();
}

class _ClientSettingsScreenState extends State<ClientSettingsScreen> {
  final ClientLoggerService _logger = ClientLoggerService();
  final DownloadSettingsService _downloadSettings = DownloadSettingsService();
  bool _debugMode = false;
  bool _isLoading = true;
  String _downloadPath = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final downloadPath = await _downloadSettings.getDownloadPath();
    setState(() {
      _debugMode = _logger.debugEnabled;
      _downloadPath = downloadPath;
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
  
  Future<void> _copyDownloadPath() async {
    await Clipboard.setData(ClipboardData(text: _downloadPath));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载路径已复制到剪贴板')),
      );
    }
  }
  
  Future<void> _selectDownloadPath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        // 验证路径
        final isValid = await _downloadSettings.validatePath(selectedDirectory);
        if (!isValid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('选择的路径无效或无法访问')),
            );
          }
          return;
        }
        
        // 保存路径
        await _downloadSettings.setDownloadPath(selectedDirectory);
        setState(() {
          _downloadPath = selectedDirectory;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载路径已更新: $selectedDirectory')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择路径失败: $e')),
        );
      }
    }
  }
  
  Future<void> _resetDownloadPath() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置下载路径'),
        content: const Text('确定要重置为默认下载路径吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final defaultPath = await _downloadSettings.resetToDefaultPath();
      setState(() {
        _downloadPath = defaultPath;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已重置为默认路径: $defaultPath')),
        );
      }
    }
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
                    '下载设置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('下载保存路径'),
                  subtitle: Text(
                    _downloadPath,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: () => _selectDownloadPath(),
                        tooltip: '选择路径',
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () => _copyDownloadPath(),
                        tooltip: '复制路径',
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => _resetDownloadPath(),
                        tooltip: '重置为默认',
                      ),
                    ],
                  ),
                  onTap: () => _selectDownloadPath(),
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
                    '• 日志文件保存在: ~/Library/Logs/remote_cam_client/\n'
                    '• 系统会自动清理旧日志，保留最近10个文件\n'
                    '• 单个日志文件最大10MB，总大小最大50MB',
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

