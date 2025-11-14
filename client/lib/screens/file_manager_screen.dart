import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:open_file/open_file.dart';
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../models/file_info.dart';
import '../models/download_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/download_settings_service.dart';

class FileManagerScreen extends StatefulWidget {
  final ApiService apiService;

  const FileManagerScreen({Key? key, required this.apiService})
      : super(key: key);

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DownloadManager _downloadManager;
  
  List<FileInfo> _pictures = [];
  List<FileInfo> _videos = [];
  List<DownloadTask> _downloadTasks = [];
  bool _isLoading = true;
  final DownloadSettingsService _downloadSettings = DownloadSettingsService();
  final Map<String, bool> _downloadedStatusCache = {}; // 缓存下载状态

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _downloadManager = DownloadManager(
      baseUrl: widget.apiService.baseUrl,
    );
    
    _initializeDownloadManager();
    _refreshFileList();
  }

  Future<void> _initializeDownloadManager() async {
    await _downloadManager.initialize();
    
    // 监听下载任务变化
    _downloadManager.tasksStream.listen((tasks) {
      if (mounted) {
        setState(() {
          _downloadTasks = tasks;
          
          // 更新下载状态缓存
          for (var task in tasks) {
            if (task.status == DownloadStatus.completed) {
              _downloadedStatusCache[task.fileName] = true;
            }
          }
        });
      }
    });
  }

  Future<void> _refreshFileList() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await widget.apiService.getFileList();
      if (result['success'] && mounted) {
        final pictures = result['pictures'] as List<FileInfo>;
        final videos = result['videos'] as List<FileInfo>;
        
        // 检查所有文件的下载状态
        await _checkDownloadStatus([...pictures, ...videos]);
        
        setState(() {
          _pictures = pictures;
          _videos = videos;
          _isLoading = false;
        });
      } else {
        _showError(result['error'] ?? '加载失败');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _showError('加载失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// 批量检查文件下载状态
  Future<void> _checkDownloadStatus(List<FileInfo> files) async {
    final downloadDir = await _downloadSettings.getDownloadPath();
    for (var file in files) {
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      _downloadedStatusCache[file.name] = await localFile.exists();
    }
  }

  Future<void> _openFile(FileInfo file) async {
    try {
      // 检查文件是否已下载（使用设置的下载路径）
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      
      if (await localFile.exists()) {
        // 文件已下载，直接打开
        final result = await OpenFile.open(localPath);
        if (result.type != ResultType.done) {
          _showError('打开文件失败: ${result.message}');
        }
      } else {
        // 文件未下载，先下载再打开
        _showInfo('文件未下载，正在下载...');
        final taskId = await _downloadManager.addDownload(
          remoteFilePath: file.path,
          fileName: file.name,
        );
        
        // 监听下载完成（只监听一次）
        StreamSubscription? subscription;
        subscription = _downloadManager.tasksStream.listen((tasks) {
          final task = tasks.firstWhere(
            (t) => t.id == taskId,
            orElse: () => tasks.first,
          );
          
          if (task.status == DownloadStatus.completed) {
            subscription?.cancel();
            if (mounted) {
              OpenFile.open(task.localFilePath);
              _showSuccess('下载完成并已打开');
            }
          } else if (task.status == DownloadStatus.failed) {
            subscription?.cancel();
            if (mounted) {
              _showError('下载失败: ${task.errorMessage ?? "未知错误"}');
            }
          }
        });
      }
    } catch (e) {
      _showError('打开文件失败: $e');
    }
  }

  Future<void> _deleteFile(FileInfo file) async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${file.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await widget.apiService.deleteFile(file.path);
      if (result['success']) {
        _showSuccess('删除成功');
        await _refreshFileList();
      } else {
        _showError(result['error'] ?? '删除失败');
      }
    } catch (e) {
      _showError('删除失败: $e');
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _downloadFile(FileInfo file) async {
    try {
      await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );
      
      final downloadDir = await _downloadSettings.getDownloadPath();
      _showSuccess('已添加到下载队列\n保存位置: $downloadDir');
      
      // 切换到下载Tab
      _tabController.animateTo(2);
    } catch (e) {
      _showError('添加下载失败: $e');
    }
  }
  
  /// 检查文件是否已下载
  Future<bool> _isFileDownloaded(FileInfo file) async {
    try {
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      return await localFile.exists();
    } catch (e) {
      return false;
    }
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshFileList,
            tooltip: '刷新',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.image),
              text: '照片 (${_pictures.length})',
            ),
            Tab(
              icon: const Icon(Icons.videocam),
              text: '视频 (${_videos.length})',
            ),
            Tab(
              icon: const Icon(Icons.download),
              text: '下载 (${_downloadTasks.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFileList(_pictures),
          _buildFileList(_videos),
          _buildDownloadList(),
        ],
      ),
    );
  }

  Widget _buildFileList(List<FileInfo> files) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (files.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无文件'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshFileList,
      child: ListView.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    file.isVideo ? Colors.red.shade100 : Colors.blue.shade100,
                child: Icon(
                  file.isVideo ? Icons.videocam : Icons.image,
                  color: file.isVideo ? Colors.red : Colors.blue,
                ),
              ),
              title: Text(file.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.formattedSize),
                  Text(
                    _formatDateTime(file.modifiedTime),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  // 显示服务端路径
                  Row(
                    children: [
                      const Icon(Icons.storage, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          file.path,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // 显示下载状态
                  if (_downloadedStatusCache[file.name] == true)
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 12, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          '已下载',
                          style: const TextStyle(fontSize: 11, color: Colors.green),
                        ),
                      ],
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () => _downloadFile(file),
                    tooltip: '下载',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    color: Colors.red,
                    onPressed: () => _deleteFile(file),
                    tooltip: '删除',
                  ),
                ],
              ),
              onTap: () => _openFile(file),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDownloadList() {
    if (_downloadTasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无下载任务'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _downloadTasks.length,
      itemBuilder: (context, index) {
        final task = _downloadTasks[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: _buildDownloadStatusIcon(task),
            title: Text(task.fileName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.isActive || task.status == DownloadStatus.pending)
                  LinearProgressIndicator(
                    value: task.progress,
                    backgroundColor: Colors.grey.shade300,
                  ),
                const SizedBox(height: 4),
                Text(_getDownloadStatusText(task)),
              ],
            ),
            trailing: _buildDownloadActions(task),
          ),
        );
      },
    );
  }

  Widget _buildDownloadStatusIcon(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.pending:
        return const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.pending, color: Colors.white),
        );
      case DownloadStatus.downloading:
        return const CircleAvatar(
          backgroundColor: Colors.blue,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      case DownloadStatus.paused:
        return const CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.pause, color: Colors.white),
        );
      case DownloadStatus.completed:
        return const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.check, color: Colors.white),
        );
      case DownloadStatus.failed:
        return const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.error, color: Colors.white),
        );
    }
  }

  Widget? _buildDownloadActions(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      return IconButton(
        icon: const Icon(Icons.pause),
        onPressed: () => _downloadManager.pauseDownload(task.id),
      );
    } else if (task.status == DownloadStatus.paused) {
      return IconButton(
        icon: const Icon(Icons.play_arrow),
        onPressed: () => _downloadManager.resumeDownload(task.id),
      );
    } else if (task.status == DownloadStatus.failed && task.canRetry) {
      return IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: () => _downloadManager.retryDownload(task.id),
      );
    } else if (task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.failed) {
      return IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _downloadManager.cancelDownload(task.id),
      );
    }
    return null;
  }

  String _getDownloadStatusText(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.pending:
        return '等待下载...';
      case DownloadStatus.downloading:
        return '${task.progressPercent}% - ${task.downloadedBytes ~/ 1024}KB / ${task.totalBytes ~/ 1024}KB';
      case DownloadStatus.paused:
        return '已暂停 - ${task.progressPercent}%';
      case DownloadStatus.completed:
        return '下载完成';
      case DownloadStatus.failed:
        return '下载失败: ${task.errorMessage ?? "未知错误"}';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _downloadManager.dispose();
    super.dispose();
  }
}

