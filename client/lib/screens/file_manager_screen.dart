import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../models/file_info.dart';
import '../models/download_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/download_settings_service.dart';

class FileManagerScreen extends StatefulWidget {
  final ApiService apiService;
  final String? highlightFileName; // 要高亮显示的文件名（用于定位）

  const FileManagerScreen({
    Key? key,
    required this.apiService,
    this.highlightFileName,
  }) : super(key: key);

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
  final Map<String, String> _thumbnailCache = {}; // 缓存缩略图路径：文件名 -> 本地缩略图路径
  Directory? _thumbnailCacheDir; // 缩略图缓存目录
  
  // 显示模式：list 或 grid
  String _viewMode = 'list'; // 'list' 或 'grid'
  double _gridItemSize = 200.0; // 网格项大小（宽度）
  final double _minGridSize = 150.0;
  final double _maxGridSize = 400.0;
  
  // 多选模式
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {}; // 选中的文件名集合
  
  // 滚动控制器（用于定位文件）
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _downloadManager = DownloadManager(
      baseUrl: widget.apiService.baseUrl,
    );
    
    _initializeThumbnailCache();
    _loadViewPreferences();
    _initializeDownloadManager();
    _refreshFileList();
  }

  /// 初始化缩略图缓存目录
  Future<void> _initializeThumbnailCache() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      _thumbnailCacheDir = Directory(path.join(cacheDir.path, 'thumbnails'));
      if (!await _thumbnailCacheDir!.exists()) {
        await _thumbnailCacheDir!.create(recursive: true);
        print('创建缩略图缓存目录: ${_thumbnailCacheDir!.path}');
      } else {
        print('缩略图缓存目录已存在: ${_thumbnailCacheDir!.path}');
        // 扫描现有缓存文件，填充内存缓存
        try {
          final files = _thumbnailCacheDir!.listSync();
          for (var file in files) {
            if (file is File && file.path.endsWith('.jpg')) {
              final fileName = path.basename(file.path).replaceAll('.jpg', '');
              _thumbnailCache[fileName] = file.path;
            }
          }
          print('已加载 ${_thumbnailCache.length} 个缓存的缩略图');
        } catch (e) {
          print('扫描缓存目录失败: $e');
        }
      }
    } catch (e, stackTrace) {
      print('初始化缩略图缓存目录失败: $e');
      print('堆栈跟踪: $stackTrace');
    }
  }
  
  /// 加载视图偏好设置
  Future<void> _loadViewPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedViewMode = prefs.getString('file_manager_view_mode');
      final savedGridSize = prefs.getDouble('file_manager_grid_size');
      
      if (mounted) {
        setState(() {
          if (savedViewMode != null && (savedViewMode == 'list' || savedViewMode == 'grid')) {
            _viewMode = savedViewMode;
          }
          
          if (savedGridSize != null && savedGridSize >= _minGridSize && savedGridSize <= _maxGridSize) {
            _gridItemSize = savedGridSize;
          }
        });
      }
    } catch (e) {
      // 忽略加载错误，使用默认值
      print('加载视图偏好设置失败: $e');
    }
  }
  
  /// 保存视图偏好设置
  Future<void> _saveViewPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('file_manager_view_mode', _viewMode);
      await prefs.setDouble('file_manager_grid_size', _gridItemSize);
      print('已保存视图偏好: mode=$_viewMode, size=$_gridItemSize');
    } catch (e) {
      print('保存视图偏好设置失败: $e');
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 如果有高亮文件，延迟滚动到该文件
    if (widget.highlightFileName != null && (_pictures.isNotEmpty || _videos.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _scrollToFile(widget.highlightFileName!);
        });
      });
    }
  }
  
  /// 滚动到指定文件
  void _scrollToFile(String fileName) {
    final allFiles = [..._pictures, ..._videos];
    final index = allFiles.indexWhere((f) => f.name == fileName);
    if (index >= 0 && _scrollController.hasClients) {
      // 计算滚动位置（让文件显示在中间）
      final itemHeight = _viewMode == 'grid' ? _gridItemSize * 1.5 : 120.0;
      final targetOffset = (index * itemHeight) - (MediaQuery.of(context).size.height / 2) + (itemHeight / 2);
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _initializeDownloadManager() async {
    await _downloadManager.initialize();
    
    // 监听下载任务变化
    _downloadManager.tasksStream.listen((tasks) {
      if (!mounted) return;
      
      // 更新下载状态缓存
      bool hasNewCompleted = false;
      for (var task in tasks) {
        if (task.status == DownloadStatus.completed) {
          final wasNotDownloaded = _downloadedStatusCache[task.fileName] != true;
          if (wasNotDownloaded) {
            hasNewCompleted = true;
          }
          // 先标记为已下载（乐观更新）
          _downloadedStatusCache[task.fileName] = true;
        }
      }
      
      // 更新UI
      if (mounted) {
        setState(() {
          _downloadTasks = tasks;
        });
        
        // 如果有新完成的下载，异步验证文件存在性并刷新UI
        if (hasNewCompleted) {
          _checkDownloadStatus([..._pictures, ..._videos]).then((_) {
            if (mounted) {
              setState(() {
                // 强制刷新UI以更新按钮状态
              });
            }
          });
        }
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

  /// 全选
  void _selectAll() {
    final currentFiles = _tabController.index == 0 
        ? _pictures 
        : (_tabController.index == 1 ? _videos : []);
    
    setState(() {
      if (_selectedFiles.length == currentFiles.length && currentFiles.isNotEmpty) {
        // 如果已全选，则取消全选
        _selectedFiles.clear();
      } else {
        // 否则全选当前标签页的所有文件
        _selectedFiles.clear();
        for (var file in currentFiles) {
          _selectedFiles.add(file.name);
        }
      }
    });
  }

  /// 批量下载
  Future<void> _batchDownload() async {
    if (_selectedFiles.isEmpty) return;
    
    int successCount = 0;
    int skipCount = 0;
    
    for (var fileName in _selectedFiles) {
      final allFiles = [..._pictures, ..._videos];
      final file = allFiles.firstWhere(
        (f) => f.name == fileName,
        orElse: () => allFiles.first,
      );
      
      // 检查是否已下载
      if (_downloadedStatusCache[fileName] == true) {
        skipCount++;
        continue;
      }
      
      // 检查是否正在下载
      final existingTask = await _downloadManager.findTaskByFileName(fileName);
      if (existingTask != null && 
          (existingTask.status == DownloadStatus.downloading || 
           existingTask.status == DownloadStatus.pending)) {
        skipCount++;
        continue;
      }
      
      try {
        await _downloadManager.addDownload(
          remoteFilePath: file.path,
          fileName: file.name,
        );
        successCount++;
      } catch (e) {
        // 忽略单个文件的错误，继续处理其他文件
      }
    }
    
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
    
    _showSuccess('批量下载完成：成功 $successCount 个，跳过 $skipCount 个');
    _tabController.animateTo(2); // 切换到下载Tab
  }

  /// 批量删除本地文件
  Future<void> _batchDeleteLocal() async {
    if (_selectedFiles.isEmpty) return;
    
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${_selectedFiles.length} 个本地文件吗？'),
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
    
    int successCount = 0;
    int failCount = 0;
    
    for (var fileName in _selectedFiles) {
      try {
        final downloadDir = await _downloadSettings.getDownloadPath();
        final localPath = path.join(downloadDir, fileName);
        final localFile = File(localPath);
        
        if (await localFile.exists()) {
          await localFile.delete();
          _downloadedStatusCache[fileName] = false;
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        failCount++;
      }
    }
    
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
    
    _showSuccess('批量删除完成：成功 $successCount 个，失败 $failCount 个');
  }

  /// 在系统资源管理器中打开并选中文件
  Future<void> _openInFileManager(FileInfo file) async {
    try {
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      
      if (!await localFile.exists()) {
        _showError('文件不存在');
        return;
      }

      // 跨平台打开文件管理器并选中文件
      if (Platform.isMacOS) {
        // macOS: open -R
        await Process.run('open', ['-R', localPath]);
      } else if (Platform.isWindows) {
        // Windows: explorer /select,filepath
        await Process.run('explorer', ['/select,', localPath]);
      } else if (Platform.isLinux) {
        // Linux: xdg-open (打开目录)
        final dirPath = path.dirname(localPath);
        await Process.run('xdg-open', [dirPath]);
      } else {
        _showError('不支持的操作系统');
      }
      
      _showSuccess('已在资源管理器中打开');
    } catch (e) {
      _showError('打开资源管理器失败: $e');
    }
  }

  /// 复制文件到剪贴板（跨平台）
  Future<void> _copyFile(FileInfo file) async {
    try {
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      
      if (!await localFile.exists()) {
        _showError('文件不存在');
        return;
      }

      // 跨平台复制文件到剪贴板
      if (Platform.isMacOS) {
        // macOS: 使用 osascript 复制文件引用
        try {
          final escapedPath = localPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
          // 使用 POSIX file 复制文件引用，而不是文件内容
          final script = 'set the clipboard to POSIX file "$escapedPath"';
          final result = await Process.run('osascript', ['-e', script]);
          if (result.exitCode == 0) {
            _showSuccess('文件已复制到剪贴板');
          } else {
            // 如果失败，复制文件路径
            await Clipboard.setData(ClipboardData(text: localPath));
            _showSuccess('文件路径已复制到剪贴板');
          }
        } catch (e) {
          // 如果失败，复制文件路径
          await Clipboard.setData(ClipboardData(text: localPath));
          _showSuccess('文件路径已复制到剪贴板');
        }
      } else if (Platform.isWindows) {
        // Windows: 使用 PowerShell 复制文件
        final escapedPath = localPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
        final result = await Process.run('powershell', [
          '-Command',
          'Set-Clipboard -Path "$escapedPath"',
        ]);
        if (result.exitCode == 0) {
          _showSuccess('文件已复制到剪贴板');
        } else {
          // 如果失败，复制文件路径
          await Clipboard.setData(ClipboardData(text: localPath));
          _showSuccess('文件路径已复制到剪贴板');
        }
      } else if (Platform.isLinux) {
        // Linux: 使用 xclip 复制文件
        try {
          // 先尝试复制文件内容
          final fileBytes = await localFile.readAsBytes();
          final process = await Process.start('xclip', ['-selection', 'clipboard', '-t', file.isVideo ? 'video/mp4' : 'image/png']);
          process.stdin.add(fileBytes);
          await process.stdin.close();
          final exitCode = await process.exitCode;
          if (exitCode == 0) {
            _showSuccess('文件已复制到剪贴板');
          } else {
            throw Exception('xclip failed with exit code $exitCode');
          }
        } catch (e) {
          // 如果 xclip 失败，尝试 xsel
          try {
            final fileBytes = await localFile.readAsBytes();
            final process = await Process.start('xsel', ['--clipboard', '--input']);
            process.stdin.add(fileBytes);
            await process.stdin.close();
            final exitCode = await process.exitCode;
            if (exitCode == 0) {
              _showSuccess('文件已复制到剪贴板');
            } else {
              throw Exception('xsel failed with exit code $exitCode');
            }
          } catch (e2) {
            // 如果都失败，复制文件路径
            await Clipboard.setData(ClipboardData(text: localPath));
            _showSuccess('文件路径已复制到剪贴板（请安装 xclip 或 xsel 以支持文件复制）');
          }
        }
      } else {
        // 其他平台：复制文件路径
        await Clipboard.setData(ClipboardData(text: localPath));
        _showSuccess('文件路径已复制到剪贴板');
      }
    } catch (e) {
      _showError('复制失败: $e');
    }
  }

  /// 删除本地文件
  Future<void> _deleteLocalFile(FileInfo file) async {
    try {
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      
      if (!await localFile.exists()) {
        _showError('文件不存在');
        return;
      }

      // 确认对话框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除本地文件 ${file.name} 吗？'),
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

      await localFile.delete();
      _downloadedStatusCache[file.name] = false;
      setState(() {});
      _showSuccess('本地文件已删除');
    } catch (e) {
      _showError('删除失败: $e');
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
      // 检查是否已下载
      final isDownloaded = _downloadedStatusCache[file.name] == true;
      if (isDownloaded) {
        _showInfo('文件已下载');
        return;
      }

      // 检查是否正在下载
      final existingTask = await _downloadManager.findTaskByFileName(file.name);
      if (existingTask != null && 
          (existingTask.status == DownloadStatus.downloading || 
           existingTask.status == DownloadStatus.pending)) {
        _showInfo('文件正在下载中');
        return;
      }

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
        title: Text(_isSelectionMode ? '已选择 ${_selectedFiles.length} 项' : '文件管理'),
        actions: [
          if (_isSelectionMode) ...[
            // 全选按钮
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
              tooltip: '全选',
            ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _selectedFiles.isEmpty ? null : _batchDownload,
              tooltip: '批量下载',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedFiles.isEmpty ? null : _batchDeleteLocal,
              tooltip: '批量删除本地文件',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedFiles.clear();
                });
              },
              tooltip: '取消选择',
            ),
          ] else ...[
            // 视图模式切换
            IconButton(
              icon: Icon(_viewMode == 'list' ? Icons.grid_view : Icons.list),
              onPressed: () async {
                setState(() {
                  _viewMode = _viewMode == 'list' ? 'grid' : 'list';
                });
                await _saveViewPreferences();
              },
              tooltip: _viewMode == 'list' ? '切换到网格视图' : '切换到列表视图',
            ),
            // 网格大小调整（仅在网格模式下显示）
            if (_viewMode == 'grid') ...[
              IconButton(
                icon: const Icon(Icons.zoom_out),
                onPressed: _gridItemSize > _minGridSize
                    ? () async {
                        setState(() {
                          _gridItemSize = (_gridItemSize - 50).clamp(_minGridSize, _maxGridSize);
                        });
                        await _saveViewPreferences();
                      }
                    : null,
                tooltip: '缩小网格',
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                onPressed: _gridItemSize < _maxGridSize
                    ? () async {
                        setState(() {
                          _gridItemSize = (_gridItemSize + 50).clamp(_minGridSize, _maxGridSize);
                        });
                        await _saveViewPreferences();
                      }
                    : null,
                tooltip: '放大网格',
              ),
            ],
            // 多选模式
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: () {
                setState(() {
                  _isSelectionMode = true;
                });
              },
              tooltip: '多选模式',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshFileList,
              tooltip: '刷新',
            ),
          ],
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

    if (_viewMode == 'grid') {
      return RefreshIndicator(
        onRefresh: _refreshFileList,
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: (MediaQuery.of(context).size.width / _gridItemSize).floor().clamp(1, 10),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.2, // 横向长方形，适合照片显示（约5:4比例）
          ),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            return _buildGridItem(file);
          },
        ),
      );
    }

    // 列表视图
    return RefreshIndicator(
      onRefresh: _refreshFileList,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final isHighlighted = widget.highlightFileName == file.name;
          return _buildListItem(file, isHighlighted: isHighlighted);
        },
      ),
    );
  }

  /// 构建列表项
  Widget _buildListItem(FileInfo file, {bool isHighlighted = false}) {
    final isDownloaded = _downloadedStatusCache[file.name] == true;
    final isSelected = _selectedFiles.contains(file.name);
    
    return Card(
      key: isHighlighted ? _highlightKey : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isHighlighted 
          ? Colors.yellow.shade100 
          : (isSelected ? Colors.blue.shade50 : null),
      elevation: isHighlighted ? 4 : null,
      child: Column(
        children: [
          ListTile(
            leading: _isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedFiles.add(file.name);
                        } else {
                          _selectedFiles.remove(file.name);
                        }
                      });
                    },
                  )
                : CircleAvatar(
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
                if (isDownloaded)
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
          ),
          // 操作按钮区域（直接显示，不折叠）
          if (!_isSelectionMode) _buildFileActionButtons(file),
        ],
      ),
    );
  }

  /// 构建网格项
  Widget _buildGridItem(FileInfo file, {bool isHighlighted = false}) {
    final isDownloaded = _downloadedStatusCache[file.name] == true;
    final isSelected = _selectedFiles.contains(file.name);
    
    return Card(
      key: isHighlighted ? _highlightKey : null,
      color: isHighlighted 
          ? Colors.yellow.shade100 
          : (isSelected ? Colors.blue.shade50 : null),
      elevation: isHighlighted ? 4 : null,
      child: InkWell(
        onTap: _isSelectionMode
            ? () {
                setState(() {
                  if (isSelected) {
                    _selectedFiles.remove(file.name);
                  } else {
                    _selectedFiles.add(file.name);
                  }
                });
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 缩略图区域 - 占用更多空间
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: file.isVideo ? Colors.red.shade100 : Colors.blue.shade100,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    // 缩略图独立于本地文件存在性，只要服务器上有文件就显示
                    child: _buildThumbnail(file),
                  ),
                  if (_isSelectionMode)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedFiles.add(file.name);
                            } else {
                              _selectedFiles.remove(file.name);
                            }
                          });
                        },
                      ),
                    ),
                  if (isDownloaded)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ),
                ],
              ),
            ),
            // 文件信息 - 紧凑布局
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 文件名和大小 - 紧凑排列
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        file.formattedSize,
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 按钮区域 - 紧贴在大小旁边
                      if (!_isSelectionMode)
                        _buildFileActionButtons(file, compact: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建缩略图（独立于本地文件存在性，只要服务器上有文件就显示缩略图）
  Widget _buildThumbnail(FileInfo file) {
    try {
      // 直接获取缩略图，不检查本地文件是否存在
      // 缩略图独立于本地文件，只要服务器上有文件就应该显示
      return FutureBuilder<String?>(
        future: _getThumbnail(file),
        builder: (context, thumbnailSnapshot) {
          if (thumbnailSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (thumbnailSnapshot.hasData && thumbnailSnapshot.data != null) {
            return Image.file(
              File(thumbnailSnapshot.data!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Icon(
                    file.isVideo ? Icons.videocam : Icons.image,
                    size: 48,
                    color: file.isVideo ? Colors.red : Colors.blue,
                  ),
                );
              },
            );
          }
          
          // 如果获取失败，显示占位符
          return Center(
            child: Icon(
              file.isVideo ? Icons.videocam : Icons.image,
              size: 48,
              color: file.isVideo ? Colors.red : Colors.blue,
            ),
          );
        },
      );
    } catch (e) {
      return Center(
        child: Icon(
          file.isVideo ? Icons.videocam : Icons.image,
          size: 48,
          color: file.isVideo ? Colors.red : Colors.blue,
        ),
      );
    }
  }

  /// 获取缩略图（照片和视频统一处理，从服务器下载并缓存）
  Future<String?> _getThumbnail(FileInfo file) async {
    try {
      // 确保缓存目录已初始化
      if (_thumbnailCacheDir == null) {
        await _initializeThumbnailCache();
      }
      if (_thumbnailCacheDir == null) {
        print('缩略图缓存目录初始化失败');
        return null;
      }

      // 构建缓存文件路径
      final thumbnailFileName = '${file.name}.jpg';
      final thumbnailFilePath = path.join(_thumbnailCacheDir!.path, thumbnailFileName);

      // 检查缓存文件是否存在（不依赖内存缓存，直接检查文件系统）
      final cachedFile = File(thumbnailFilePath);
      if (await cachedFile.exists()) {
        print('使用缓存的缩略图: $thumbnailFilePath');
        // 更新内存缓存
        _thumbnailCache[file.name] = thumbnailFilePath;
        return thumbnailFilePath;
      }

      print('缓存不存在，从服务器下载缩略图: ${file.name}');
      // 从服务器下载缩略图
      final thumbnailBytes = await widget.apiService.downloadThumbnail(file.path, file.isVideo);
      if (thumbnailBytes == null) {
        print('下载缩略图失败: ${file.name}');
        return null;
      }

      print('下载成功，保存缩略图到缓存: $thumbnailFilePath (大小: ${thumbnailBytes.length} 字节)');
      // 保存到缓存目录
      await cachedFile.writeAsBytes(thumbnailBytes);

      // 更新内存缓存
      _thumbnailCache[file.name] = thumbnailFilePath;
      print('缩略图已缓存: $thumbnailFilePath');
      return thumbnailFilePath;
    } catch (e, stackTrace) {
      print('获取缩略图失败: $e');
      print('堆栈跟踪: $stackTrace');
      return null;
    }
  }

  /// 构建文件操作按钮（直接显示）
  Widget _buildFileActionButtons(FileInfo file, {bool compact = false}) {
    final isDownloaded = _downloadedStatusCache[file.name] == true;
    
    if (compact) {
      // 紧凑模式（网格视图）- 紧凑排列
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.download, size: 16),
            onPressed: isDownloaded ? null : () => _downloadFile(file),
            tooltip: '下载',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
              maxWidth: 24,
              maxHeight: 24,
            ),
            iconSize: 16,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 16),
            onPressed: isDownloaded ? () => _openInFileManager(file) : null,
            tooltip: '在资源管理器中打开',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
              maxWidth: 24,
              maxHeight: 24,
            ),
            iconSize: 16,
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: isDownloaded ? () => _copyFile(file) : null,
            tooltip: '复制文件',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
              maxWidth: 24,
              maxHeight: 24,
            ),
            iconSize: 16,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, size: 16),
            color: Colors.red,
            onPressed: isDownloaded ? () => _deleteLocalFile(file) : null,
            tooltip: '删除本地文件',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
              maxWidth: 24,
              maxHeight: 24,
            ),
            iconSize: 16,
          ),
        ],
      );
    }
    
    // 完整模式（列表视图）
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('下载', style: TextStyle(fontSize: 12)),
              onPressed: isDownloaded ? null : () => _downloadFile(file),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('打开', style: TextStyle(fontSize: 12)),
              onPressed: isDownloaded ? () => _openInFileManager(file) : null,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制', style: TextStyle(fontSize: 12)),
              onPressed: isDownloaded ? () => _copyFile(file) : null,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('删除', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: isDownloaded ? () => _deleteLocalFile(file) : null,
            ),
          ),
        ],
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
    _scrollController.dispose();
    _downloadManager.dispose();
    super.dispose();
  }
}

