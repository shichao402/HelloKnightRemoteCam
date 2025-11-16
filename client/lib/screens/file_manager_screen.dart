import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../models/file_info.dart';
import '../models/download_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/download_settings_service.dart';
import '../services/logger_service.dart';

class FileManagerScreen extends StatefulWidget {
  final ApiService apiService;
  final String? highlightFileName; // 要高亮显示的文件名（用于定位）
  final bool showAppBar; // 是否显示 AppBar（嵌入模式时设为 false）

  const FileManagerScreen({
    Key? key,
    required this.apiService,
    this.highlightFileName,
    this.showAppBar = true, // 默认显示 AppBar
  }) : super(key: key);

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  late DownloadManager _downloadManager;
  final ClientLoggerService _logger = ClientLoggerService();

  List<FileInfo> _pictures = [];
  List<FileInfo> _videos = [];
  List<DownloadTask> _downloadTasks = [];
  bool _isLoading = true;
  bool _isLoadingMore = false; // 是否正在加载更多
  final DownloadSettingsService _downloadSettings = DownloadSettingsService();
  final Map<String, bool> _downloadedStatusCache = {}; // 缓存下载状态
  final Map<String, String> _thumbnailCache = {}; // 缓存缩略图路径：文件名 -> 本地缩略图路径
  final Map<String, Future<String?>> _thumbnailFutureCache =
      {}; // 缓存 Future：文件名 -> Future<String?>
  Directory? _thumbnailCacheDir; // 缩略图缓存目录

  // 分页相关
  int _currentPage = 1;
  static const int _pageSize = 20; // 每页20个文件
  bool _hasMore = true;
  int? _lastUpdateTime; // 最后更新时间戳（用于增量获取）

  // 显示模式：固定为 grid
  double _gridItemSize = 200.0; // 网格项大小（宽度）
  final double _minGridSize = 150.0;
  final double _maxGridSize = 400.0;

  // 文件组织方式：none, day, week, month
  String _groupMode = 'none'; // 'none', 'day', 'week', 'month'

  // 多选模式
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {}; // 选中的文件名集合

  // 滚动控制器（用于定位文件和检测滚动到底部）
  final ScrollController _scrollController = ScrollController();
  final ScrollController _gridScrollController =
      ScrollController(); // 网格视图的滚动控制器
  final GlobalKey _highlightKey = GlobalKey();

  // WebSocket通知消息订阅（用于接收server的新文件通知）
  StreamSubscription? _webSocketSubscription;
  // 自动下载监听订阅
  StreamSubscription? _autoDownloadSubscription;

  @override
  void initState() {
    super.initState();
    _downloadManager = DownloadManager(
      baseUrl: widget.apiService.baseUrl,
    );

    // 监听滚动，实现滚动到底部自动加载更多
    _scrollController.addListener(_onScroll);
    _gridScrollController.addListener(_onGridScroll);

    _initializeThumbnailCache();
    _loadViewPreferences();
    _initializeDownloadManager();
    _refreshFileList();
    _startFileListRefreshTimer(); // 启动WebSocket连接并监听通知
    // 连接WebSocket（用于API调用）
    widget.apiService.connectWebSocket();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _gridScrollController.removeListener(_onGridScroll);
    _scrollController.dispose();
    _gridScrollController.dispose();
    _downloadManager.dispose();
    _webSocketSubscription?.cancel();
    _autoDownloadSubscription?.cancel();
    _completionSubscription?.cancel();
    // 取消所有超时定时器
    for (var timer in _completionTimeouts.values) {
      timer.cancel();
    }
    _completionTimeouts.clear();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// 启动WebSocket连接（监听server的新文件通知）
  void _startFileListRefreshTimer() {
    _logger.log('准备启动WebSocket通知监听', tag: 'FILE_MANAGER');
    _connectToWebSocketNotifications();
  }

  /// 连接到WebSocket通知流（监听服务器推送的通知）
  void _connectToWebSocketNotifications() async {
    try {
      // 确保ApiService的WebSocket已连接
      await widget.apiService.connectWebSocket();

      // 监听通知消息
      final notificationStream = widget.apiService.webSocketNotifications;
      if (notificationStream != null) {
        _webSocketSubscription = notificationStream.listen(
          (notification) {
            if (!mounted) {
              return;
            }

            try {
              final event = notification['event'] as String?;
              final data = notification['data'] as Map<String, dynamic>?;

              // 处理新文件通知
              if (event == 'new_files' && data != null) {
                // 收到新文件通知，直接使用通知中的文件信息
                _handleNewFilesNotification(data);
              }
            } catch (e) {
              // 解析失败，忽略
            }
          },
          onError: (error) {
            // 连接失败，5秒后重试
            if (mounted) {
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) {
                  _connectToWebSocketNotifications();
                }
              });
            }
          },
          cancelOnError: false,
        );
      }
    } catch (e) {
      // 连接失败，5秒后重试
      if (mounted) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            _connectToWebSocketNotifications();
          }
        });
      }
    }
  }

  /// 列表视图滚动监听（检测是否滚动到底部）
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // 距离底部200像素时加载更多
      _loadMoreFiles();
    }
  }

  /// 网格视图滚动监听（检测是否滚动到底部）
  void _onGridScroll() {
    if (_gridScrollController.position.pixels >=
        _gridScrollController.position.maxScrollExtent - 200) {
      // 距离底部200像素时加载更多
      _loadMoreFiles();
    }
  }

  /// 初始化缩略图缓存目录
  Future<void> _initializeThumbnailCache() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      _thumbnailCacheDir = Directory(path.join(cacheDir.path, 'thumbnails'));
      if (!await _thumbnailCacheDir!.exists()) {
        await _thumbnailCacheDir!.create(recursive: true);
        _logger.log('创建缩略图缓存目录: ${_thumbnailCacheDir!.path}',
            tag: 'THUMBNAIL_CACHE');
      } else {
        _logger.log('缩略图缓存目录已存在: ${_thumbnailCacheDir!.path}',
            tag: 'THUMBNAIL_CACHE');
        // 扫描现有缓存文件，填充内存缓存
        try {
          final files = _thumbnailCacheDir!.listSync();
          for (var file in files) {
            if (file is File && file.path.endsWith('.jpg')) {
              final fileName = path.basename(file.path).replaceAll('.jpg', '');
              _thumbnailCache[fileName] = file.path;
            }
          }
          _logger.log('已加载 ${_thumbnailCache.length} 个缓存的缩略图',
              tag: 'THUMBNAIL_CACHE');
        } catch (e) {
          _logger.logError('扫描缓存目录失败', error: e);
        }
      }
    } catch (e, stackTrace) {
      _logger.logError('初始化缩略图缓存目录失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 加载视图偏好设置
  Future<void> _loadViewPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedGridSize = prefs.getDouble('file_manager_grid_size');
      final savedGroupMode = prefs.getString('file_manager_group_mode');

      if (mounted) {
        setState(() {
          if (savedGridSize != null &&
              savedGridSize >= _minGridSize &&
              savedGridSize <= _maxGridSize) {
            _gridItemSize = savedGridSize;
          }

          if (savedGroupMode != null &&
              (savedGroupMode == 'none' ||
                  savedGroupMode == 'day' ||
                  savedGroupMode == 'week' ||
                  savedGroupMode == 'month')) {
            _groupMode = savedGroupMode;
          }
        });
      }
    } catch (e) {
      // 忽略加载错误，使用默认值
      _logger.logError('加载视图偏好设置失败', error: e);
    }
  }

  /// 保存视图偏好设置
  Future<void> _saveViewPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('file_manager_grid_size', _gridItemSize);
      await prefs.setString('file_manager_group_mode', _groupMode);
      _logger.log('已保存视图偏好: size=$_gridItemSize, group=$_groupMode',
          tag: 'VIEW_PREFERENCES');
    } catch (e) {
      _logger.logError('保存视图偏好设置失败', error: e);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 如果有高亮文件，延迟滚动到该文件
    if (widget.highlightFileName != null &&
        (_pictures.isNotEmpty || _videos.isNotEmpty)) {
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
      final itemHeight = _gridItemSize * 1.5;
      final targetOffset = (index * itemHeight) -
          (MediaQuery.of(context).size.height / 2) +
          (itemHeight / 2);
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  // 下载完成监听订阅
  StreamSubscription<DownloadTask>? _completionSubscription;
  // 下载完成超时保护映射：文件名 -> 超时定时器
  final Map<String, Timer> _completionTimeouts = {};

  // 防抖定时器：用于合并多次状态更新
  Timer? _debounceTimer;
  bool _pendingStateUpdate = false;

  Future<void> _initializeDownloadManager() async {
    await _downloadManager.initialize();

    // 监听下载任务变化（用于更新下载进度）
    _downloadManager.tasksStream.listen((tasks) {
      if (!mounted) return;

      // 检查是否有变化
      bool needsUpdate = false;
      String updateReason = '';

      // 检查下载任务列表长度是否有变化
      if (_downloadTasks.length != tasks.length) {
        needsUpdate = true;
        updateReason = '任务列表长度变化: ${_downloadTasks.length} -> ${tasks.length}';
        _logger.log('检测到任务列表长度变化: ${_downloadTasks.length} -> ${tasks.length}',
            tag: 'FILE_MANAGER');
      } else {
        // 检查任务状态或进度是否有变化
        // 注意：由于 tasks 中的对象可能是同一个引用，我们需要比较值而不是引用
        // 优化：使用 Map 提高查找效率（如果任务数量较多）
        final oldTasksMap = <String, DownloadTask>{};
        for (var oldTask in _downloadTasks) {
          oldTasksMap[oldTask.id] = oldTask;
        }

        for (var task in tasks) {
          // 查找对应的旧任务
          final oldTask = oldTasksMap[task.id];
          if (oldTask == null) {
            // 新任务，需要更新
            needsUpdate = true;
            updateReason = '新任务: ${task.fileName}';
            _logger.log('检测到新任务: ${task.fileName}', tag: 'FILE_MANAGER');
            break;
          }

          // 如果任务状态变化，需要更新
          if (oldTask.status != task.status) {
            needsUpdate = true;
            updateReason =
                '状态变化: ${task.fileName}, ${oldTask.status} -> ${task.status}';
            _logger.log(
                '检测到状态变化: ${task.fileName}, ${oldTask.status} -> ${task.status}',
                tag: 'FILE_MANAGER');
            break;
          }

          // 如果正在下载，检查进度变化
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.pending) {
            // 对于正在下载的任务，检查进度是否有变化
            // 注意：即使百分比相同，只要字节数变化就更新UI，确保进度条能平滑更新
            // 使用值比较，避免引用问题
            final oldBytes = oldTask.downloadedBytes;
            final newBytes = task.downloadedBytes;
            final oldTotal = oldTask.totalBytes;
            final newTotal = task.totalBytes;

            if (oldBytes != newBytes || oldTotal != newTotal) {
              final oldProgress =
                  oldTotal > 0 ? (oldBytes * 100 / oldTotal).round() : 0;
              final newProgress =
                  newTotal > 0 ? (newBytes * 100 / newTotal).round() : 0;
              // 即使百分比相同，只要字节数变化就更新UI（确保进度条能平滑更新）
              needsUpdate = true;
              updateReason =
                  '进度变化: ${task.fileName}, $oldProgress% -> $newProgress% ($oldBytes/$oldTotal -> $newBytes/$newTotal)';
              _logger.log(
                  '检测到进度变化: ${task.fileName}, $oldProgress% -> $newProgress% ($oldBytes/$oldTotal -> $newBytes/$newTotal)',
                  tag: 'FILE_MANAGER');
              break;
            }
          } else {
            // 对于其他状态的任务，检查下载字节数是否有变化
            if (oldTask.downloadedBytes != task.downloadedBytes) {
              needsUpdate = true;
              updateReason =
                  '字节数变化: ${task.fileName}, ${oldTask.downloadedBytes} -> ${task.downloadedBytes}';
              _logger.log(
                  '检测到字节数变化: ${task.fileName}, ${oldTask.downloadedBytes} -> ${task.downloadedBytes}',
                  tag: 'FILE_MANAGER');
              break;
            }
          }
        }
      }

      // 如果有变化，立即更新UI
      if (needsUpdate) {
        _logger.log('UI更新下载进度: $updateReason', tag: 'FILE_MANAGER');
        // 优化：预先构建旧任务Map，避免在setState中重复查找
        final oldTasksMap = <String, DownloadTask>{};
        for (var oldTask in _downloadTasks) {
          oldTasksMap[oldTask.id] = oldTask;
        }

        setState(() {
          // 创建新列表，避免引用问题
          // 优化：只对实际变化的任务使用 copyWith，减少不必要的对象创建
          _downloadTasks = tasks.map((task) {
            final oldTask = oldTasksMap[task.id];
            // 如果对象引用相同或值完全相同，直接使用原对象
            if (oldTask != null &&
                (identical(oldTask, task) ||
                    (oldTask.downloadedBytes == task.downloadedBytes &&
                        oldTask.totalBytes == task.totalBytes &&
                        oldTask.status == task.status))) {
              return oldTask; // 复用原对象
            }
            // 需要创建新对象
            return task.copyWith(
              totalBytes: task.totalBytes,
              downloadedBytes: task.downloadedBytes,
              status: task.status,
            );
          }).toList();
        });
      }
      // 移除调试日志（生产环境不需要）
    });

    // 监听下载完成事件（使用回调机制）
    _completionSubscription = _downloadManager.completionStream.listen((task) {
      if (!mounted) return;

      _logger.log('收到下载完成回调: ${task.fileName}', tag: 'DOWNLOAD_MANAGER');

      // 取消该文件的超时定时器（如果存在）
      _completionTimeouts[task.fileName]?.cancel();
      _completionTimeouts.remove(task.fileName);

      // 更新下载状态缓存
      _downloadedStatusCache[task.fileName] = true;

      // 检查文件列表中的对应文件并更新UI
      _updateFileDownloadStatus(task.fileName);

      // 设置超时保护：如果1秒后状态仍未更新，强制检查
      _completionTimeouts[task.fileName] =
          Timer(const Duration(seconds: 1), () {
        if (mounted) {
          _logger.log('超时保护触发，强制检查文件状态: ${task.fileName}',
              tag: 'DOWNLOAD_MANAGER');
          _updateFileDownloadStatus(task.fileName, forceCheck: true);
        }
      });
    });
  }

  /// 更新文件的下载状态
  Future<void> _updateFileDownloadStatus(String fileName,
      {bool forceCheck = false}) async {
    if (!mounted) return;

    // 查找文件列表中的对应文件
    final now = DateTime.now();
    final file = [..._pictures, ..._videos].firstWhere(
      (f) => f.name == fileName,
      orElse: () => FileInfo(
        name: fileName,
        path: '',
        size: 0,
        createdTime: now,
        modifiedTime: now,
      ),
    );

    if (file.name == fileName && file.path.isNotEmpty) {
      // 检查文件是否存在
      await _checkDownloadStatus([file]);

      // 使用防抖机制，避免频繁刷新
      // _checkDownloadStatus 内部已经会触发防抖更新，这里不需要再次调用 setState
      _logger.log('文件状态已更新: $fileName', tag: 'DOWNLOAD_MANAGER');
    } else if (forceCheck) {
      // 强制检查：即使文件不在列表中，也检查下载目录
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, fileName);
      final localFile = File(localPath);
      final exists = await localFile.exists();

      if (exists) {
        _downloadedStatusCache[fileName] = true;
        if (mounted) {
          // 使用防抖机制，避免频繁刷新
          _debouncedSetState(reason: '强制检查文件存在: $fileName');
          _logger.log('强制检查完成，文件存在: $fileName', tag: 'DOWNLOAD_MANAGER');
        }
      }
    }
  }

  /// 刷新文件列表（完整刷新，重置分页）
  Future<void> _refreshFileList() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
      _lastUpdateTime = null; // 重置增量更新时间
    });

    try {
      final result = await widget.apiService.getFileList(
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (result['success'] && mounted) {
        final pictures = result['pictures'] as List<FileInfo>;
        final videos = result['videos'] as List<FileInfo>;

        // 检查所有文件的下载状态
        await _checkDownloadStatus([...pictures, ...videos]);

        // 更新最后更新时间（使用最新文件的修改时间）
        if (pictures.isNotEmpty || videos.isNotEmpty) {
          final allFiles = [...pictures, ...videos];
          allFiles.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
          _lastUpdateTime = allFiles.first.modifiedTime.millisecondsSinceEpoch;
        }

        _logger.log(
            '执行 setState 刷新文件列表，将触发所有缩略图重建: 照片 ${pictures.length} 张, 视频 ${videos.length} 个',
            tag: 'THUMBNAIL_REFRESH');
        setState(() {
          _pictures = pictures;
          _videos = videos;
          _hasMore = result['hasMore'] as bool? ?? false;
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

  /// 处理新文件通知（直接使用通知中的文件信息）
  Future<void> _handleNewFilesNotification(Map<String, dynamic> data) async {
    try {
      _logger.log('收到新文件通知，开始处理', tag: 'FILE_NOTIFICATION');
      final fileType = data['fileType'] as String?;
      final filesData = data['files'] as List<dynamic>?;

      _logger.log('文件类型: $fileType, 文件数量: ${filesData?.length ?? 0}',
          tag: 'FILE_NOTIFICATION');

      if (filesData == null || filesData.isEmpty) {
        _logger.log('没有文件信息，回退到增量刷新', tag: 'FILE_NOTIFICATION');
        await _incrementalRefreshFileList();
        return;
      }

      // 解析文件信息
      final List<FileInfo> newFiles = [];
      for (var fileJson in filesData) {
        try {
          final fileInfo = FileInfo.fromJson(fileJson as Map<String, dynamic>);
          newFiles.add(fileInfo);
          _logger.log('解析文件成功: ${fileInfo.name}', tag: 'FILE_NOTIFICATION');
        } catch (e) {
          _logger.logError('解析文件信息失败', error: e);
        }
      }

      if (newFiles.isEmpty) {
        _logger.log('解析后没有有效文件，跳过更新', tag: 'FILE_NOTIFICATION');
        return;
      }

      _logger.log('成功解析 ${newFiles.length} 个文件，准备更新UI',
          tag: 'FILE_NOTIFICATION');

      // 检查新文件的下载状态
      await _checkDownloadStatus(newFiles);

      // 合并新文件到现有列表（去重，按修改时间排序）
      final existingFileNames = <String>{};
      for (var file in [..._pictures, ..._videos]) {
        existingFileNames.add(file.name);
      }

      // 检查是否有真正的新文件
      final List<FileInfo> trulyNewFiles = [];
      final List<FileInfo> updatedExistingFiles = [];

      for (var file in newFiles) {
        if (!existingFileNames.contains(file.name)) {
          trulyNewFiles.add(file);
        } else {
          updatedExistingFiles.add(file);
        }
      }

      // 如果没有新文件且没有需要更新的文件，直接返回
      if (trulyNewFiles.isEmpty && updatedExistingFiles.isEmpty) {
        _logger.log('没有新文件或更新，跳过UI更新', tag: 'FILE_NOTIFICATION');
        return;
      }

      final updatedPictures = <FileInfo>[..._pictures];
      final updatedVideos = <FileInfo>[..._videos];
      bool needsSort = false;

      // 处理新文件：插入到列表开头（因为新文件时间戳最大）
      for (var file in trulyNewFiles) {
        if (fileType == 'image' || file.isImage) {
          updatedPictures.insert(0, file);
          needsSort = true;
        } else if (fileType == 'video' || file.isVideo) {
          updatedVideos.insert(0, file);
          needsSort = true;
        }
      }

      // 处理更新的文件：只更新已存在的文件，不改变位置
      for (var file in updatedExistingFiles) {
        if (fileType == 'image' || file.isImage) {
          final index = updatedPictures.indexWhere((f) => f.name == file.name);
          if (index >= 0) {
            updatedPictures[index] = file;
          }
        } else if (fileType == 'video' || file.isVideo) {
          final index = updatedVideos.indexWhere((f) => f.name == file.name);
          if (index >= 0) {
            updatedVideos[index] = file;
          }
        }
      }

      // 只在有新文件时才排序
      // 由于新文件的时间戳应该是最新的，插入到开头后，只需要对新文件部分排序
      // 如果新文件的时间戳确实比现有文件都新，就不需要全量排序
      if (needsSort && trulyNewFiles.isNotEmpty) {
        // 获取新文件的最大时间戳
        final newFilesMaxTime = trulyNewFiles
            .map((f) => f.modifiedTime)
            .reduce((a, b) => a.isAfter(b) ? a : b);

        // 处理照片列表
        final newPicturesCount =
            trulyNewFiles.where((f) => fileType == 'image' || f.isImage).length;
        if (newPicturesCount > 0 && updatedPictures.length > newPicturesCount) {
          // 检查新文件是否确实比现有文件都新
          final oldestExistingTime =
              updatedPictures[newPicturesCount].modifiedTime;
          if (newFilesMaxTime.isAfter(oldestExistingTime) ||
              newFilesMaxTime.isAtSameMomentAs(oldestExistingTime)) {
            // 新文件都在前面，只对新文件部分排序
            final newPictures = updatedPictures.sublist(0, newPicturesCount);
            newPictures
                .sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
            updatedPictures.replaceRange(0, newPicturesCount, newPictures);
          } else {
            // 需要全量排序
            updatedPictures
                .sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
          }
        } else {
          // 只有新文件或列表为空，直接排序
          updatedPictures
              .sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
        }

        // 处理视频列表
        final newVideosCount =
            trulyNewFiles.where((f) => fileType == 'video' || f.isVideo).length;
        if (newVideosCount > 0 && updatedVideos.length > newVideosCount) {
          final oldestExistingTime = updatedVideos[newVideosCount].modifiedTime;
          final newVideosMaxTime = trulyNewFiles
              .where((f) => fileType == 'video' || f.isVideo)
              .map((f) => f.modifiedTime)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          if (newVideosMaxTime.isAfter(oldestExistingTime) ||
              newVideosMaxTime.isAtSameMomentAs(oldestExistingTime)) {
            // 新文件都在前面，只对新文件部分排序
            final newVideos = updatedVideos.sublist(0, newVideosCount);
            newVideos.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
            updatedVideos.replaceRange(0, newVideosCount, newVideos);
          } else {
            // 需要全量排序
            updatedVideos
                .sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
          }
        } else {
          // 只有新文件或列表为空，直接排序
          updatedVideos
              .sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
        }
      }

      // 更新最后更新时间
      if (updatedPictures.isNotEmpty || updatedVideos.isNotEmpty) {
        final allFiles = [...updatedPictures, ...updatedVideos];
        allFiles.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
        _lastUpdateTime = allFiles.first.modifiedTime.millisecondsSinceEpoch;
      }

      _logger.log(
          '更新文件列表: 照片 ${updatedPictures.length} 张, 视频 ${updatedVideos.length} 个',
          tag: 'FILE_NOTIFICATION');

      if (mounted) {
        // 取消防抖定时器，立即更新（因为这是主要的文件列表更新）
        _debounceTimer?.cancel();
        _pendingStateUpdate = false;
        _logger.log(
            '执行 setState 更新文件列表，将触发所有缩略图重建: 照片 ${updatedPictures.length} 张, 视频 ${updatedVideos.length} 个',
            tag: 'THUMBNAIL_REFRESH');
        setState(() {
          _pictures = updatedPictures;
          _videos = updatedVideos;
        });
        _logger.log('UI已更新', tag: 'FILE_NOTIFICATION');
        _logger.log(
            '检查自动下载条件: fileType=$fileType, updatedPictures.length=${updatedPictures.length}, updatedVideos.length=${updatedVideos.length}',
            tag: 'FILE_NOTIFICATION');

        // 自动下载最新照片/视频
        if (fileType == 'image' && updatedPictures.isNotEmpty) {
          final latestPicture = updatedPictures.first;
          _logger.log('准备自动下载照片: ${latestPicture.name}',
              tag: 'FILE_NOTIFICATION');
          try {
            await _autoDownloadFile(latestPicture);
            _logger.log('自动下载调用完成', tag: 'FILE_NOTIFICATION');
          } catch (e, stackTrace) {
            _logger.logError('自动下载调用失败', error: e, stackTrace: stackTrace);
          }
        } else if (fileType == 'video' && updatedVideos.isNotEmpty) {
          final latestVideo = updatedVideos.first;
          _logger.log('准备自动下载视频: ${latestVideo.name}',
              tag: 'FILE_NOTIFICATION');
          try {
            await _autoDownloadFile(latestVideo);
            _logger.log('自动下载调用完成', tag: 'FILE_NOTIFICATION');
          } catch (e, stackTrace) {
            _logger.logError('自动下载调用失败', error: e, stackTrace: stackTrace);
          }
        } else {
          _logger.log(
              '自动下载条件不满足: fileType=$fileType, picturesEmpty=${updatedPictures.isEmpty}, videosEmpty=${updatedVideos.isEmpty}',
              tag: 'FILE_NOTIFICATION');
        }
      } else {
        _logger.log('Widget未挂载，跳过自动下载', tag: 'FILE_NOTIFICATION');
      }
    } catch (e) {
      _logger.logError('处理新文件通知失败', error: e);
      // 如果处理失败，回退到增量刷新
      await _incrementalRefreshFileList();
    }
  }

  /// 增量更新文件列表（只获取新增/修改的文件）
  Future<void> _incrementalRefreshFileList() async {
    if (_lastUpdateTime == null) {
      // 如果没有最后更新时间，执行完整刷新
      await _refreshFileList();
      return;
    }

    try {
      // 减去1秒，确保能获取到刚刚创建的文件（即使时间戳相同）
      final since = _lastUpdateTime! - 1000;
      final result = await widget.apiService.getFileList(
        since: since,
      );

      if (result['success'] && mounted) {
        final newPictures = result['pictures'] as List<FileInfo>;
        final newVideos = result['videos'] as List<FileInfo>;

        if (newPictures.isEmpty && newVideos.isEmpty) {
          // 没有新文件，不需要更新
          return;
        }

        // 检查新文件的下载状态
        await _checkDownloadStatus([...newPictures, ...newVideos]);

        // 合并新文件到现有列表（去重，按修改时间排序）
        final existingFileNames = <String>{};
        for (var file in [..._pictures, ..._videos]) {
          existingFileNames.add(file.name);
        }

        final updatedPictures = <FileInfo>[..._pictures];
        final updatedVideos = <FileInfo>[..._videos];

        for (var file in newPictures) {
          if (!existingFileNames.contains(file.name)) {
            updatedPictures.add(file);
            existingFileNames.add(file.name);
          } else {
            // 更新已存在的文件
            final index =
                updatedPictures.indexWhere((f) => f.name == file.name);
            if (index >= 0) {
              updatedPictures[index] = file;
            }
          }
        }

        for (var file in newVideos) {
          if (!existingFileNames.contains(file.name)) {
            updatedVideos.add(file);
            existingFileNames.add(file.name);
          } else {
            // 更新已存在的文件
            final index = updatedVideos.indexWhere((f) => f.name == file.name);
            if (index >= 0) {
              updatedVideos[index] = file;
            }
          }
        }

        // 按修改时间排序
        updatedPictures
            .sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
        updatedVideos.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));

        // 更新最后更新时间
        final allFiles = [...updatedPictures, ...updatedVideos];
        if (allFiles.isNotEmpty) {
          allFiles.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
          _lastUpdateTime = allFiles.first.modifiedTime.millisecondsSinceEpoch;
        }

        _logger.log(
            '执行 setState 增量更新文件列表，将触发所有缩略图重建: 照片 ${updatedPictures.length} 张, 视频 ${updatedVideos.length} 个',
            tag: 'THUMBNAIL_REFRESH');
        setState(() {
          _pictures = updatedPictures;
          _videos = updatedVideos;
        });
      }
    } catch (e) {
      // 增量更新失败不影响UI，只记录错误
      _logger.logError('增量更新文件列表失败', error: e);
    }
  }

  /// 加载更多文件（分页加载）
  Future<void> _loadMoreFiles() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final result = await widget.apiService.getFileList(
        page: nextPage,
        pageSize: _pageSize,
      );

      if (result['success'] && mounted) {
        final newPictures = result['pictures'] as List<FileInfo>;
        final newVideos = result['videos'] as List<FileInfo>;

        // 检查新文件的下载状态
        await _checkDownloadStatus([...newPictures, ...newVideos]);

        _logger.log(
            '执行 setState 加载更多文件，将触发所有缩略图重建: 新增照片 ${newPictures.length} 张, 新增视频 ${newVideos.length} 个',
            tag: 'THUMBNAIL_REFRESH');
        setState(() {
          _pictures.addAll(newPictures);
          _videos.addAll(newVideos);
          _currentPage = nextPage;
          _hasMore = result['hasMore'] as bool? ?? false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      _showError('加载更多失败: $e');
    }
  }

  /// 批量检查文件下载状态
  Future<void> _checkDownloadStatus(List<FileInfo> files) async {
    final downloadDir = await _downloadSettings.getDownloadPath();
    bool hasChanged = false;
    for (var file in files) {
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      final exists = await localFile.exists();
      final oldStatus = _downloadedStatusCache[file.name];
      _downloadedStatusCache[file.name] = exists;
      if (oldStatus != exists) {
        hasChanged = true;
        _logger.log('文件下载状态变化: ${file.name}, 旧状态=$oldStatus, 新状态=$exists',
            tag: 'DOWNLOAD_STATUS');
      }
    }
    // 如果状态有变化，使用防抖机制延迟更新UI
    // 注意：虽然会触发 setState，但 Future 缓存可以避免缩略图重新加载
    if (hasChanged && mounted) {
      _logger.log('检测到下载状态变化，使用防抖机制更新UI: 变化的文件数=${files.length}',
          tag: 'DOWNLOAD_STATUS');
      _debouncedSetState(reason: '下载状态变化');
    }
  }

  /// 统一更新文件列表中的文件状态（避免刷新整个列表）
  /// 使用 copyWith 更新文件对象，只更新变化的文件，不影响其他文件
  /// 这样可以避免缩略图重新加载，提升性能
  void _updateFileInList({
    required String filePath,
    required FileInfo Function(FileInfo) updateFn,
    String? reason,
  }) {
    if (!mounted) return;

    bool hasUpdate = false;

    // 更新照片列表中的文件
    final pictureIndex = _pictures.indexWhere((f) => f.path == filePath);
    if (pictureIndex != -1) {
      final oldFile = _pictures[pictureIndex];
      final newFile = updateFn(oldFile);
      if (oldFile != newFile) {
        _pictures[pictureIndex] = newFile;
        hasUpdate = true;
        _logger.log('更新照片列表中的文件: ${oldFile.name}, reason=$reason',
            tag: 'FILE_UPDATE');
      }
    }

    // 更新视频列表中的文件
    final videoIndex = _videos.indexWhere((f) => f.path == filePath);
    if (videoIndex != -1) {
      final oldFile = _videos[videoIndex];
      final newFile = updateFn(oldFile);
      if (oldFile != newFile) {
        _videos[videoIndex] = newFile;
        hasUpdate = true;
        _logger.log('更新视频列表中的文件: ${oldFile.name}, reason=$reason',
            tag: 'FILE_UPDATE');
      }
    }

    // 只有当文件确实存在且状态有变化时才更新UI
    if (hasUpdate) {
      setState(() {
        // 文件对象已更新，Flutter 会通过 ValueKey 识别哪些项需要重建
        // 由于使用了稳定的 key（file.name），只有对应的项会更新
      });
    }
  }

  /// 防抖的 setState：合并短时间内的多次更新
  /// 注意：这个方法会触发整个列表重建，应该尽量避免使用
  /// 优先使用 _updateFileInList 来更新单个文件的状态
  void _debouncedSetState({String? reason}) {
    _pendingStateUpdate = true;
    _debounceTimer?.cancel();
    _logger.log('防抖 setState 请求: reason=$reason', tag: 'THUMBNAIL_REFRESH');
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (_pendingStateUpdate && mounted) {
        _pendingStateUpdate = false;
        _logger.log('执行防抖 setState，将触发所有缩略图重建: reason=$reason',
            tag: 'THUMBNAIL_REFRESH');
        setState(() {
          // 状态缓存已更新，这里只是触发UI刷新
        });
      }
    });
  }

  /// 自动下载文件（收到新文件通知时自动下载）
  Future<void> _autoDownloadFile(FileInfo file) async {
    try {
      // 检查是否已经在下载中或已完成
      final existingTask = await _downloadManager.findTaskByFileName(file.name);

      if (existingTask != null) {
        if (existingTask.status == DownloadStatus.downloading ||
            existingTask.status == DownloadStatus.pending) {
          // 已经在下载中
          _logger.log('文件已在下载中: ${file.name}', tag: 'AUTO_DOWNLOAD');
          return;
        }

        if (existingTask.status == DownloadStatus.completed) {
          // 已经下载完成，更新状态缓存
          final downloadDir = await _downloadSettings.getDownloadPath();
          final localPath = path.join(downloadDir, file.name);
          final localFile = File(localPath);
          if (await localFile.exists()) {
            _downloadedStatusCache[file.name] = true;
            if (mounted) {
              // 使用防抖机制，避免频繁刷新
              _debouncedSetState(reason: '自动下载文件已存在: ${file.name}');
            }
          }
          _logger.log('文件已下载完成: ${file.name}', tag: 'AUTO_DOWNLOAD');
          return;
        }
      }

      // 检查文件是否已存在
      final downloadDir = await _downloadSettings.getDownloadPath();
      final localPath = path.join(downloadDir, file.name);
      final localFile = File(localPath);
      if (await localFile.exists()) {
        _downloadedStatusCache[file.name] = true;
        if (mounted) {
          // 使用防抖机制，避免频繁刷新
          _debouncedSetState(reason: '自动下载检查文件已存在: ${file.name}');
        }
        _logger.log('文件已存在: ${file.name}', tag: 'AUTO_DOWNLOAD');
        return;
      }

      // 添加下载任务
      _logger.log('开始自动下载: ${file.name}', tag: 'AUTO_DOWNLOAD');
      final taskId = await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );

      // 取消之前的订阅
      _autoDownloadSubscription?.cancel();

      // 监听下载完成（只监听一次）
      _autoDownloadSubscription = _downloadManager.tasksStream.listen((tasks) {
        final task = tasks.firstWhere(
          (t) => t.id == taskId,
          orElse: () => tasks.first,
        );

        if (task.status == DownloadStatus.completed) {
          _autoDownloadSubscription?.cancel();
          _autoDownloadSubscription = null;
          // 更新下载状态缓存
          _downloadedStatusCache[task.fileName] = true;
          if (mounted) {
            // 使用防抖机制，避免频繁刷新
            _debouncedSetState(reason: '自动下载完成: ${task.fileName}');
          }
          _logger.log('自动下载完成: ${task.fileName}', tag: 'AUTO_DOWNLOAD');
        } else if (task.status == DownloadStatus.failed) {
          _autoDownloadSubscription?.cancel();
          _autoDownloadSubscription = null;
          _logger.log('自动下载失败: ${task.fileName}, 错误: ${task.errorMessage}',
              tag: 'AUTO_DOWNLOAD');
        }
      });
    } catch (e) {
      _logger.logError('自动下载失败: ${file.name}', error: e);
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
    final allFiles = [..._pictures, ..._videos];

    setState(() {
      if (_selectedFiles.length == allFiles.length && allFiles.isNotEmpty) {
        // 如果已全选，则取消全选
        _selectedFiles.clear();
      } else {
        // 否则全选所有文件
        _selectedFiles.clear();
        for (var file in allFiles) {
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
          final escapedPath =
              localPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
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
        final escapedPath =
            localPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
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
          final process = await Process.start('xclip', [
            '-selection',
            'clipboard',
            '-t',
            file.isVideo ? 'video/mp4' : 'image/png'
          ]);
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
            final process =
                await Process.start('xsel', ['--clipboard', '--input']);
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
    // 检查是否已标记星标
    if (file.isStarred) {
      _showError('无法删除已标记星标的文件，请先取消星标');
      return;
    }

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
    // 检查是否已标记星标
    if (file.isStarred) {
      _showError('无法删除已标记星标的文件，请先取消星标');
      return;
    }

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

  Future<void> _toggleStarred(FileInfo file) async {
    try {
      _logger.log('切换文件星标状态: ${file.name}', tag: 'FILE_MANAGER');
      final result = await widget.apiService.toggleStarred(file.path);
      if (result['success']) {
        final newStarred = result['isStarred'] as bool? ?? false;
        _showSuccess(newStarred ? '已标记星标' : '已取消星标');

        // 使用统一的更新方法，只更新当前文件的状态，不刷新整个列表
        _updateFileInList(
          filePath: file.path,
          updateFn: (f) => f.copyWith(isStarred: newStarred),
          reason: '切换星标状态',
        );
      } else {
        _showError(result['error'] ?? '操作失败');
      }
    } catch (e, stackTrace) {
      _logger.logError('切换文件星标状态失败', error: e, stackTrace: stackTrace);
      _showError('操作失败: $e');
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
    _logger.log('用户点击下载按钮: ${file.name}', tag: 'FILE_MANAGER');
    try {
      // 检查是否已下载
      final isDownloaded = _downloadedStatusCache[file.name] == true;
      if (isDownloaded) {
        _logger.log('文件已下载，跳过: ${file.name}', tag: 'FILE_MANAGER');
        _showInfo('文件已下载');
        return;
      }

      // 检查是否正在下载
      final existingTask = await _downloadManager.findTaskByFileName(file.name);
      if (existingTask != null &&
          (existingTask.status == DownloadStatus.downloading ||
              existingTask.status == DownloadStatus.pending)) {
        _logger.log('文件正在下载中，跳过: ${file.name}, 状态=${existingTask.status}',
            tag: 'FILE_MANAGER');
        _showInfo('文件正在下载中');
        return;
      }

      _logger.log('调用下载管理器添加下载: ${file.name}', tag: 'FILE_MANAGER');
      final taskId = await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );
      _logger.log('下载任务已添加，任务ID: $taskId', tag: 'FILE_MANAGER');

      final downloadDir = await _downloadSettings.getDownloadPath();
      _showSuccess('已添加到下载队列\n保存位置: $downloadDir');
    } catch (e) {
      _logger.logError('添加下载失败: ${file.name}', error: e);
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
    // 构建工具栏
    Widget buildToolbar() {
      return Container(
        color: Theme.of(context).appBarTheme.backgroundColor ?? Colors.blue,
        child: Row(
          children: [
            if (!widget.showAppBar)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _isSelectionMode
                        ? '已选择 ${_selectedFiles.length} 项'
                        : '文件管理',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (_isSelectionMode) ...[
              // 全选按钮
              IconButton(
                icon:
                    const Icon(Icons.select_all, color: Colors.white, size: 20),
                onPressed: _selectAll,
                tooltip: '全选',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white, size: 20),
                onPressed: _selectedFiles.isEmpty ? null : _batchDownload,
                tooltip: '批量下载',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.white, size: 20),
                onPressed: _selectedFiles.isEmpty ? null : _batchDeleteLocal,
                tooltip: '批量删除本地文件',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedFiles.clear();
                  });
                },
                tooltip: '取消选择',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ] else ...[
              // 网格大小调整
              ...[
                IconButton(
                  icon:
                      const Icon(Icons.zoom_out, color: Colors.white, size: 20),
                  onPressed: _gridItemSize > _minGridSize
                      ? () async {
                          setState(() {
                            _gridItemSize = (_gridItemSize - 50)
                                .clamp(_minGridSize, _maxGridSize);
                          });
                          await _saveViewPreferences();
                        }
                      : null,
                  tooltip: '缩小网格',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.zoom_in, color: Colors.white, size: 20),
                  onPressed: _gridItemSize < _maxGridSize
                      ? () async {
                          setState(() {
                            _gridItemSize = (_gridItemSize + 50)
                                .clamp(_minGridSize, _maxGridSize);
                          });
                          await _saveViewPreferences();
                        }
                      : null,
                  tooltip: '放大网格',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ],
              // 分组模式选择
              PopupMenuButton<String>(
                icon: Icon(
                  _getGroupModeIcon(_groupMode),
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: '文件组织方式',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onSelected: (value) async {
                  setState(() {
                    _groupMode = value;
                  });
                  await _saveViewPreferences();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'none',
                    child: Row(
                      children: [
                        Icon(Icons.view_list),
                        SizedBox(width: 8),
                        Text('无分组'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'day',
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today),
                        SizedBox(width: 8),
                        Text('按天'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'week',
                    child: Row(
                      children: [
                        Icon(Icons.view_week),
                        SizedBox(width: 8),
                        Text('按周'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'month',
                    child: Row(
                      children: [
                        Icon(Icons.calendar_view_month),
                        SizedBox(width: 8),
                        Text('按月'),
                      ],
                    ),
                  ),
                ],
              ),
              // 多选模式
              IconButton(
                icon:
                    const Icon(Icons.checklist, color: Colors.white, size: 20),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = true;
                  });
                },
                tooltip: '多选模式',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: _refreshFileList,
                tooltip: '刷新',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(
                  _isSelectionMode ? '已选择 ${_selectedFiles.length} 项' : '文件管理'),
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
                    onPressed:
                        _selectedFiles.isEmpty ? null : _batchDeleteLocal,
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
                  // 网格大小调整
                  ...[
                    IconButton(
                      icon: const Icon(Icons.zoom_out),
                      onPressed: _gridItemSize > _minGridSize
                          ? () async {
                              setState(() {
                                _gridItemSize = (_gridItemSize - 50)
                                    .clamp(_minGridSize, _maxGridSize);
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
                                _gridItemSize = (_gridItemSize + 50)
                                    .clamp(_minGridSize, _maxGridSize);
                              });
                              await _saveViewPreferences();
                            }
                          : null,
                      tooltip: '放大网格',
                    ),
                  ],
                  // 分组模式选择
                  PopupMenuButton<String>(
                    icon: Icon(_getGroupModeIcon(_groupMode)),
                    tooltip: '文件组织方式',
                    onSelected: (value) async {
                      setState(() {
                        _groupMode = value;
                      });
                      await _saveViewPreferences();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'none',
                        child: Row(
                          children: [
                            Icon(Icons.view_list),
                            SizedBox(width: 8),
                            Text('无分组'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'day',
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today),
                            SizedBox(width: 8),
                            Text('按天'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'week',
                        child: Row(
                          children: [
                            Icon(Icons.view_week),
                            SizedBox(width: 8),
                            Text('按周'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'month',
                        child: Row(
                          children: [
                            Icon(Icons.calendar_view_month),
                            SizedBox(width: 8),
                            Text('按月'),
                          ],
                        ),
                      ),
                    ],
                  ),
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
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              if (!widget.showAppBar) ...[
                SizedBox(
                  width: constraints.maxWidth,
                  child: buildToolbar(),
                ),
              ],
              Expanded(
                child: _buildAllFilesList(), // 合并的照片和视频列表
              ),
            ],
          );
        },
      ),
    );
  }

  /// 获取文件的分组键（用于分组显示）
  String _getGroupKey(FileInfo file) {
    final date = file.modifiedTime;

    switch (_groupMode) {
      case 'day':
        // 按天分组：YYYY-MM-DD
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case 'week':
        // 按周分组：找到该周的周一日期 YYYY-MM-DD
        final weekday = date.weekday; // 1=Monday, 7=Sunday
        final monday = date.subtract(Duration(days: weekday - 1));
        return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
      case 'month':
        // 按月分组：YYYY-MM
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
      default:
        return '';
    }
  }

  /// 格式化分组标题
  String _formatGroupTitle(String groupKey) {
    if (groupKey.isEmpty) return '';

    switch (_groupMode) {
      case 'day':
        // 解析日期并格式化：YYYY-MM-DD -> YYYY年MM月DD日
        final parts = groupKey.split('-');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          final date = DateTime(year, month, day);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));

          if (date == today) {
            return '今天';
          } else if (date == yesterday) {
            return '昨天';
          } else {
            return '$year年$month月$day日';
          }
        }
        return groupKey;
      case 'week':
        // 解析周一的日期并格式化：YYYY-MM-DD -> YYYY年MM月DD日 - YYYY年MM月DD日
        final parts = groupKey.split('-');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          final monday = DateTime(year, month, day);
          final sunday = monday.add(const Duration(days: 6));
          return '${year}年${month}月${day}日 - ${sunday.year}年${sunday.month}月${sunday.day}日';
        }
        return groupKey;
      case 'month':
        // 解析月份并格式化：YYYY-MM -> YYYY年MM月
        final parts = groupKey.split('-');
        if (parts.length == 2) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          return '$year年$month月';
        }
        return groupKey;
      default:
        return groupKey;
    }
  }

  /// 对文件列表进行分组
  Map<String, List<FileInfo>> _groupFiles(List<FileInfo> files) {
    if (_groupMode == 'none') {
      return {'': files};
    }

    final grouped = <String, List<FileInfo>>{};
    for (var file in files) {
      final key = _getGroupKey(file);
      grouped.putIfAbsent(key, () => []).add(file);
    }

    // 对每个分组内的文件按时间排序（最新的在前）
    for (var key in grouped.keys) {
      grouped[key]!.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    }

    return grouped;
  }

  /// 构建合并的照片和视频列表（用图标区分）
  Widget _buildAllFilesList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 合并照片和视频，按修改时间排序
    final allFiles = [..._pictures, ..._videos]
      ..sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));

    if (allFiles.isEmpty) {
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

    // 对文件进行分组
    final groupedFiles = _groupFiles(allFiles);
    final groupKeys = groupedFiles.keys.toList();

    // 对分组键进行排序（最新的在前）
    if (_groupMode != 'none') {
      groupKeys.sort((a, b) {
        // 按时间倒序排序
        if (_groupMode == 'day' || _groupMode == 'week') {
          // YYYY-MM-DD 格式可以直接字符串比较
          return b.compareTo(a);
        } else if (_groupMode == 'month') {
          // YYYY-MM 格式可以直接字符串比较
          return b.compareTo(a);
        }
        return 0;
      });
    }

    return RefreshIndicator(
      onRefresh: _refreshFileList,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 使用实际可用宽度计算列数，避免溢出
          // 考虑 padding (左右各8px) 和 spacing (列间距8px)
          const padding = 16.0; // 左右各8px
          const spacing = 8.0; // 列间距
          final availableWidth = constraints.maxWidth - padding;

          // 计算列数：availableWidth = crossAxisCount * itemWidth + (crossAxisCount - 1) * spacing
          // 即：availableWidth = crossAxisCount * (itemWidth + spacing) - spacing
          // crossAxisCount = (availableWidth + spacing) / (itemWidth + spacing)
          // 确保至少减去一个 spacing 来避免溢出
          final crossAxisCount =
              ((availableWidth - spacing) / (_gridItemSize + spacing))
                  .floor()
                  .clamp(1, 10);

          // 使用CustomScrollView支持分组标题跨列显示
          return CustomScrollView(
            controller: _gridScrollController,
            slivers: [
              // 构建分组和文件
              ...groupKeys.map((key) {
                final files = groupedFiles[key]!;
                return [
                  // 分组标题（如果有分组模式）
                  if (_groupMode != 'none' && key.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildGroupHeader(
                          _formatGroupTitle(key), crossAxisCount),
                    ),
                  // 文件网格
                  SliverPadding(
                    padding: const EdgeInsets.all(8),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.2,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index < files.length) {
                            return _buildGridItem(files[index]);
                          }
                          return const SizedBox.shrink();
                        },
                        childCount: files.length,
                        addAutomaticKeepAlives: true, // 保持列表项状态，避免不必要的重建
                        addRepaintBoundaries: true, // 添加重绘边界，优化性能
                      ),
                    ),
                  ),
                ];
              }).expand((x) => x),
              // 加载更多指示器
              if (_hasMore)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _isLoadingMore
                          ? const CircularProgressIndicator()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 构建分组标题
  Widget _buildGroupHeader(String title, int crossAxisCount) {
    if (_groupMode == 'none' || title.isEmpty) {
      return const SizedBox.shrink();
    }

    // 网格视图：标题占满整行
    if (crossAxisCount > 1) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
      );
    }

    // 单列时：标准标题样式
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 使用实际可用宽度计算列数，避免溢出
          // 考虑 padding (左右各8px) 和 spacing (列间距8px)
          const padding = 16.0; // 左右各8px
          const spacing = 8.0; // 列间距
          final availableWidth = constraints.maxWidth - padding;

          // 计算列数：availableWidth = crossAxisCount * itemWidth + (crossAxisCount - 1) * spacing
          // 即：availableWidth = crossAxisCount * (itemWidth + spacing) - spacing
          // crossAxisCount = (availableWidth + spacing) / (itemWidth + spacing)
          // 确保至少减去一个 spacing 来避免溢出
          final crossAxisCount =
              ((availableWidth - spacing) / (_gridItemSize + spacing))
                  .floor()
                  .clamp(1, 10);

          return GridView.builder(
            controller: _gridScrollController,
            padding: const EdgeInsets.all(8),
            addAutomaticKeepAlives: true, // 保持列表项状态，避免不必要的重建
            addRepaintBoundaries: true, // 添加重绘边界，优化性能
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: 8,
              childAspectRatio: 1.2,
            ),
            itemCount: files.length + (_hasMore ? 1 : 0), // 如果有更多，添加一个加载指示器
            itemBuilder: (context, index) {
              if (index == files.length) {
                // 加载更多指示器
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _isLoadingMore
                        ? const CircularProgressIndicator()
                        : const SizedBox.shrink(),
                  ),
                );
              }
              final file = files[index];
              return _buildGridItem(file);
            },
          );
        },
      ),
    );
  }

  /// 构建网格项
  Widget _buildGridItem(FileInfo file, {bool isHighlighted = false}) {
    final isSelected = _selectedFiles.contains(file.name);

    // 使用稳定的 key 来避免不必要的重建
    return Card(
      key: ValueKey('grid_item_${file.name}'),
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
        onDoubleTap: !_isSelectionMode
            ? () {
                _logger.log('双击打开文件: ${file.name}', tag: 'FILE_MANAGER');
                _openFile(file);
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
                      color: file.isVideo
                          ? Colors.red.shade100
                          : Colors.blue.shade100,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    // 缩略图独立于本地文件存在性，只要服务器上有文件就显示
                    child: _buildThumbnail(file),
                  ),
                  // 文件类型角标 - 左上角
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: file.isVideo
                            ? Colors.red.withOpacity(0.9)
                            : Colors.blue.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            file.isVideo ? Icons.videocam : Icons.image,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            file.isVideo ? '视频' : '照片',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isSelectionMode)
                    Positioned(
                      top: 4,
                      right: 4,
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
                  // 星标按钮 - 右上角（多选模式下不显示，避免与复选框重叠）
                  if (!_isSelectionMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _toggleStarred(file),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            file.isStarred ? Icons.star : Icons.star_border,
                            color: file.isStarred ? Colors.amber : Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
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
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Text(
                        file.formattedSize,
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateTime(file.createdTime),
                        style: const TextStyle(fontSize: 8, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(),
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
      _logger.log('构建缩略图 Widget: ${file.name}', tag: 'THUMBNAIL_REFRESH');

      // 如果缩略图路径已经在缓存中，直接显示，避免使用 FutureBuilder 导致的闪烁
      if (_thumbnailCache.containsKey(file.name)) {
        final cachedPath = _thumbnailCache[file.name]!;
        _logger.log('使用缓存的缩略图路径直接显示: ${file.name}, path=$cachedPath',
            tag: 'THUMBNAIL_REFRESH');
        return RepaintBoundary(
          key: ValueKey('thumbnail_${file.name}'),
          child: Image.file(
            File(cachedPath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              _logger.log('缓存的缩略图加载失败: ${file.name}, error=$error',
                  tag: 'THUMBNAIL_REFRESH');
              // 如果缓存的路径失效，清除缓存并使用 FutureBuilder 重新加载
              _thumbnailCache.remove(file.name);
              _thumbnailFutureCache.remove(file.name);
              return Center(
                child: Icon(
                  file.isVideo ? Icons.videocam : Icons.image,
                  size: 48,
                  color: file.isVideo ? Colors.red : Colors.blue,
                ),
              );
            },
          ),
        );
      }

      // 如果缓存中没有路径，使用 FutureBuilder 异步加载
      // 使用稳定的 key 和 RepaintBoundary 来避免不必要的重建
      return RepaintBoundary(
        key: ValueKey('thumbnail_${file.name}'),
        child: FutureBuilder<String?>(
          future: _getThumbnail(file),
          builder: (context, thumbnailSnapshot) {
            _logger.log(
                'FutureBuilder builder 被调用: ${file.name}, connectionState=${thumbnailSnapshot.connectionState}, hasData=${thumbnailSnapshot.hasData}',
                tag: 'THUMBNAIL_REFRESH');

            if (thumbnailSnapshot.connectionState == ConnectionState.waiting) {
              _logger.log('缩略图加载中: ${file.name}', tag: 'THUMBNAIL_REFRESH');
              return const Center(child: CircularProgressIndicator());
            }

            if (thumbnailSnapshot.hasData && thumbnailSnapshot.data != null) {
              _logger.log('显示缩略图: ${file.name}, path=${thumbnailSnapshot.data}',
                  tag: 'THUMBNAIL_REFRESH');
              return Image.file(
                File(thumbnailSnapshot.data!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  _logger.log('缩略图加载失败: ${file.name}, error=$error',
                      tag: 'THUMBNAIL_REFRESH');
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
            _logger.log('缩略图获取失败，显示占位符: ${file.name}',
                tag: 'THUMBNAIL_REFRESH');
            return Center(
              child: Icon(
                file.isVideo ? Icons.videocam : Icons.image,
                size: 48,
                color: file.isVideo ? Colors.red : Colors.blue,
              ),
            );
          },
        ),
      );
    } catch (e, stackTrace) {
      _logger.logError('构建缩略图异常: ${file.name}',
          error: e, stackTrace: stackTrace);
      return Center(
        child: Icon(
          file.isVideo ? Icons.videocam : Icons.image,
          size: 48,
          color: file.isVideo ? Colors.red : Colors.blue,
        ),
      );
    }
  }

  /// 获取缩略图 Future（缓存 Future 本身，避免重复创建）
  Future<String?> _getThumbnail(FileInfo file) {
    // 如果已经有缓存的 Future，直接返回（避免重复创建）
    if (_thumbnailFutureCache.containsKey(file.name)) {
      _logger.log('使用缓存的 Future: ${file.name}', tag: 'THUMBNAIL_REFRESH');
      return _thumbnailFutureCache[file.name]!;
    }

    // 创建新的 Future 并缓存
    final future = _loadThumbnail(file);
    _thumbnailFutureCache[file.name] = future;
    return future;
  }

  /// 实际加载缩略图（照片和视频统一处理，从服务器下载并缓存）
  Future<String?> _loadThumbnail(FileInfo file) async {
    try {
      _logger.log('开始获取缩略图: ${file.name}', tag: 'THUMBNAIL_REFRESH');
      // 确保缓存目录已初始化
      if (_thumbnailCacheDir == null) {
        await _initializeThumbnailCache();
      }
      if (_thumbnailCacheDir == null) {
        _logger.log('缩略图缓存目录初始化失败: ${file.name}', tag: 'THUMBNAIL_REFRESH');
        return null;
      }

      // 构建缓存文件路径
      final thumbnailFileName = '${file.name}.jpg';
      final thumbnailFilePath =
          path.join(_thumbnailCacheDir!.path, thumbnailFileName);

      // 检查缓存文件是否存在（不依赖内存缓存，直接检查文件系统）
      final cachedFile = File(thumbnailFilePath);
      if (await cachedFile.exists()) {
        _logger.log('使用缓存的缩略图: ${file.name}, path=$thumbnailFilePath',
            tag: 'THUMBNAIL_REFRESH');
        // 更新内存缓存
        _thumbnailCache[file.name] = thumbnailFilePath;
        return thumbnailFilePath;
      }

      _logger.log('缓存不存在，从服务器下载缩略图: ${file.name}', tag: 'THUMBNAIL_REFRESH');
      // 从服务器下载缩略图
      final thumbnailBytes =
          await widget.apiService.downloadThumbnail(file.path, file.isVideo);
      if (thumbnailBytes == null) {
        _logger.log('下载缩略图失败: ${file.name}', tag: 'THUMBNAIL_REFRESH');
        return null;
      }

      _logger.log(
          '下载成功，保存缩略图到缓存: ${file.name}, path=$thumbnailFilePath, 大小=${thumbnailBytes.length} 字节',
          tag: 'THUMBNAIL_REFRESH');
      // 保存到缓存目录
      await cachedFile.writeAsBytes(thumbnailBytes);

      // 更新内存缓存
      _thumbnailCache[file.name] = thumbnailFilePath;
      _logger.log('缩略图已缓存: ${file.name}, path=$thumbnailFilePath',
          tag: 'THUMBNAIL_REFRESH');
      return thumbnailFilePath;
    } catch (e, stackTrace) {
      _logger.logError('获取缩略图异常: ${file.name}',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 构建文件操作按钮（直接显示）
  Widget _buildFileActionButtons(FileInfo file, {bool compact = false}) {
    final isDownloaded = _downloadedStatusCache[file.name] == true;

    // 查找该文件的下载任务
    final downloadTask = _downloadTasks.firstWhere(
      (task) => task.fileName == file.name,
      orElse: () => DownloadTask(
        id: '',
        remoteFilePath: '',
        localFilePath: '',
        fileName: '',
        totalBytes: 0,
      ),
    );

    // 检查是否正在下载（包括下载中和等待中）
    final isDownloading = downloadTask.fileName == file.name &&
        (downloadTask.status == DownloadStatus.downloading ||
            downloadTask.status == DownloadStatus.pending);

    // 调试日志：记录按钮构建时的状态
    if (isDownloading) {
      final progress = downloadTask.totalBytes > 0
          ? (downloadTask.downloadedBytes * 100 / downloadTask.totalBytes)
              .round()
          : 0;
      _logger.log(
          '构建下载按钮: ${file.name}, 状态=${downloadTask.status}, 进度=$progress% (${downloadTask.downloadedBytes}/${downloadTask.totalBytes})',
          tag: 'FILE_MANAGER');
    }

    if (compact) {
      // 紧凑模式（网格视图）- 紧凑排列
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 如果正在下载，显示圆形进度条；否则显示下载按钮
          isDownloading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: downloadTask.progress,
                    strokeWidth: 2.5,
                    backgroundColor: Colors.grey.shade300,
                  ),
                )
              : IconButton(
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
            onPressed: (isDownloaded && !file.isStarred)
                ? () => _deleteLocalFile(file)
                : null,
            tooltip: file.isStarred ? '无法删除已标记星标的文件' : '删除本地文件',
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

    // 默认返回紧凑模式（现在只有网格视图）
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 如果正在下载，显示圆形进度条；否则显示下载按钮
        isDownloading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: downloadTask.progress,
                  strokeWidth: 2.5,
                  backgroundColor: Colors.grey.shade300,
                ),
              )
            : IconButton(
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
          onPressed: (isDownloaded && !file.isStarred)
              ? () => _deleteLocalFile(file)
              : null,
          tooltip: file.isStarred ? '无法删除已标记星标的文件' : '删除本地文件',
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

  /// 获取分组模式对应的图标
  IconData _getGroupModeIcon(String mode) {
    switch (mode) {
      case 'day':
        return Icons.calendar_today;
      case 'week':
        return Icons.view_week;
      case 'month':
        return Icons.calendar_view_month;
      default:
        return Icons.view_list;
    }
  }
}
