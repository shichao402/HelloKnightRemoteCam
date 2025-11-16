import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../models/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadManagerScreen extends StatefulWidget {
  final ApiService apiService;

  const DownloadManagerScreen({
    Key? key,
    required this.apiService,
  }) : super(key: key);

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> {
  late DownloadManager _downloadManager;
  List<DownloadTask> _activeTasks = []; // 正在下载的任务
  List<DownloadTask> _completedTasks = []; // 已下载的任务
  StreamSubscription<List<DownloadTask>>? _tasksSubscription;
  final TextEditingController _daysController = TextEditingController(text: '1');
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _downloadManager = DownloadManager(baseUrl: widget.apiService.baseUrl);
    _loadDaysPreference();
    _initializeDownloadManager();
    _loadCompletedTasks();
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    _downloadManager.dispose();
    _daysController.dispose();
    super.dispose();
  }

  // 加载保存的天数偏好
  Future<void> _loadDaysPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDays = prefs.getInt('download_delete_days') ?? 1;
      _daysController.text = savedDays.toString();
    } catch (e) {
      // 使用默认值
      _daysController.text = '1';
    }
  }

  // 保存天数偏好
  Future<void> _saveDaysPreference(int days) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('download_delete_days', days);
    } catch (e) {
      // 忽略错误
    }
  }

  Future<void> _initializeDownloadManager() async {
    await _downloadManager.initialize();
    
    // 监听下载任务变化
    _tasksSubscription = _downloadManager.tasksStream.listen((tasks) {
      if (!mounted) return;
      
      setState(() {
        _activeTasks = tasks.where((t) => 
          t.status != DownloadStatus.completed && 
          t.status != DownloadStatus.failed
        ).toList();
      });
    });
    
    // 立即获取当前任务
    final currentTasks = _downloadManager.getTasks();
    setState(() {
      _activeTasks = currentTasks.where((t) => 
        t.status != DownloadStatus.completed && 
        t.status != DownloadStatus.failed
      ).toList();
      _isLoading = false;
    });
  }

  Future<void> _loadCompletedTasks() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final completed = await _downloadManager.getCompletedTasks();
      if (mounted) {
        setState(() {
          _completedTasks = completed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showError('加载已完成任务失败: $e');
      }
    }
  }

  Future<void> _deleteTask(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除下载记录 "${task.fileName}" 吗？\n\n注意：这只会删除记录，不会删除本地文件。'),
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
      final success = await _downloadManager.deleteCompletedTask(task.id);
      if (success) {
        _showSuccess('删除成功');
        _loadCompletedTasks();
      } else {
        _showError('删除失败');
      }
    } catch (e) {
      _showError('删除失败: $e');
    }
  }

  Future<void> _deleteOldTasks() async {
    final daysText = _daysController.text.trim();
    if (daysText.isEmpty) {
      _showError('请输入天数');
      return;
    }

    final days = int.tryParse(daysText);
    if (days == null || days < 0) {
      _showError('请输入有效的天数');
      return;
    }

    // 保存偏好
    await _saveDaysPreference(days);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 $days 天之前的所有下载记录吗？\n\n注意：这只会删除记录，不会删除本地文件。'),
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
      final deletedCount = await _downloadManager.deleteCompletedTasksOlderThan(days);
      if (mounted) {
        _showSuccess('已删除 $deletedCount 条记录');
        _loadCompletedTasks();
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
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildDownloadStatusIcon(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.pending:
        return const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.hourglass_empty, color: Colors.white, size: 20),
        );
      case DownloadStatus.downloading:
        return const CircleAvatar(
          backgroundColor: Colors.blue,
          child: Icon(Icons.download, color: Colors.white, size: 20),
        );
      case DownloadStatus.paused:
        return const CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.pause, color: Colors.white, size: 20),
        );
      case DownloadStatus.completed:
        return const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.check, color: Colors.white, size: 20),
        );
      case DownloadStatus.failed:
        return const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.error, color: Colors.white, size: 20),
        );
    }
  }

  Widget? _buildDownloadActions(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      return IconButton(
        icon: const Icon(Icons.pause),
        onPressed: () => _downloadManager.pauseDownload(task.id),
        tooltip: '暂停',
      );
    } else if (task.status == DownloadStatus.paused) {
      return IconButton(
        icon: const Icon(Icons.play_arrow),
        onPressed: () => _downloadManager.resumeDownload(task.id),
        tooltip: '继续',
      );
    } else if (task.status == DownloadStatus.failed && task.canRetry) {
      return IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: () => _downloadManager.retryDownload(task.id),
        tooltip: '重试',
      );
    } else if (task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.failed) {
      return IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _downloadManager.cancelDownload(task.id),
        tooltip: '取消',
      );
    }
    return null;
  }

  String _getDownloadStatusText(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.pending:
        return '等待下载...';
      case DownloadStatus.downloading:
        return '${task.progressPercent}% - ${_formatBytes(task.downloadedBytes)} / ${_formatBytes(task.totalBytes)}';
      case DownloadStatus.paused:
        return '已暂停 - ${task.progressPercent}%';
      case DownloadStatus.completed:
        return '下载完成 - ${task.endTime != null ? _formatDateTime(task.endTime!) : ""}';
      case DownloadStatus.failed:
        return '下载失败: ${task.errorMessage ?? "未知错误"}';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildActiveTaskItem(DownloadTask task) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _buildDownloadStatusIcon(task),
        title: Text(task.fileName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.isActive || task.status == DownloadStatus.pending)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: Colors.grey.shade300,
                ),
              ),
            const SizedBox(height: 4),
            Text(_getDownloadStatusText(task)),
          ],
        ),
        trailing: _buildDownloadActions(task),
      ),
    );
  }

  Widget _buildCompletedTaskItem(DownloadTask task) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _buildDownloadStatusIcon(task),
        title: Text(task.fileName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('大小: ${_formatBytes(task.totalBytes)}'),
            if (task.endTime != null)
              Text('完成时间: ${_formatDateTime(task.endTime!)}'),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteTask(task),
          tooltip: '删除记录',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadCompletedTasks();
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 删除旧记录工具栏
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text('删除'),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: _daysController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const Text('天之前的记录'),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _deleteOldTasks,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ),
                // 内容区域
                Expanded(
                  child: _activeTasks.isEmpty && _completedTasks.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.download_done, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('暂无下载记录'),
                            ],
                          ),
                        )
                      : ListView(
                          children: [
                            // 正在下载
                            if (_activeTasks.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  '正在下载 (${_activeTasks.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ..._activeTasks.map((task) => _buildActiveTaskItem(task)),
                            ],
                            // 已下载
                            if (_completedTasks.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  '已下载 (${_completedTasks.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ..._completedTasks.map((task) => _buildCompletedTaskItem(task)),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

