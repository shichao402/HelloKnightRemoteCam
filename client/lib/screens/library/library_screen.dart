import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/media/media.dart';
import '../../models/download_task.dart';
import '../../services/api_service_manager.dart';
import '../../services/download_manager.dart';
import 'media_grid_item.dart';
import 'media_detail_screen.dart';

/// 媒体库主页面
/// 本地管理为主，远端补充（Google Photos 风格）
class LibraryScreen extends StatefulWidget {
  /// 可选的外部传入的 MediaLibraryService
  final MediaLibraryService? libraryService;

  const LibraryScreen({super.key, this.libraryService});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

/// 分组模式
enum GroupMode {
  none,       // 不分组
  byDay,      // 按天分组
  byMonth,    // 按月分组
}

class _LibraryScreenState extends State<LibraryScreen> {
  MediaLibraryService? _libraryService;
  final ApiServiceManager _apiManager = ApiServiceManager();

  List<MediaItem> _mediaItems = [];
  MediaFilter _filter = MediaFilter.defaultFilter;
  bool _isLoading = true;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  String? _error;

  // 筛选状态
  MediaType? _typeFilter;
  bool _starredOnly = false;

  // 排序状态
  MediaSortBy _sortBy = MediaSortBy.createdAt;
  SortOrder _sortOrder = SortOrder.descending;

  // 分组状态
  GroupMode _groupMode = GroupMode.byDay;

  // 待同步数量
  int _pendingSyncCount = 0;

  // 媒体流订阅
  StreamSubscription<List<MediaItem>>? _mediaStreamSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAndLoad();
  }

  @override
  void dispose() {
    _mediaStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeAndLoad() async {
    try {
      // 使用外部传入的 service 或创建新的实例
      if (widget.libraryService != null) {
        _libraryService = widget.libraryService;
      } else {
        _libraryService = MediaLibraryService.instance;
        await _libraryService!.init();
      }
      
      // 监听媒体数据变化，智能更新
      _mediaStreamSubscription = _libraryService!.mediaStream.listen((items) {
        // 数据变化时智能更新（不显示 loading，避免整个列表闪烁）
        _updateMediaSmart(items);
      });
      
      await _loadMedia();
    } catch (e) {
      setState(() {
        _error = '初始化失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 智能更新媒体列表（只更新变化的部分，不触发全量刷新）
  void _updateMediaSmart(List<MediaItem> newItems) {
    // 应用当前筛选条件
    var filteredItems = newItems;
    
    // 类型筛选
    if (_filter.type != null) {
      filteredItems = filteredItems.where((item) => item.type == _filter.type).toList();
    }
    
    // 星标筛选
    if (_filter.isStarred != null) {
      filteredItems = filteredItems.where((item) => item.isStarred == _filter.isStarred).toList();
    }
    
    // 搜索筛选
    if (_filter.searchQuery != null && _filter.searchQuery!.isNotEmpty) {
      final query = _filter.searchQuery!.toLowerCase();
      filteredItems = filteredItems.where((item) => item.name.toLowerCase().contains(query)).toList();
    }
    
    // 排序
    filteredItems = _sortItems(filteredItems);
    
    // 计算待同步数量
    final pending = filteredItems.where((item) => 
      item.syncStatus == SyncStatus.pending ||
      item.syncStatus == SyncStatus.failed
    ).length;
    
    // 检查是否真的有变化（避免不必要的 setState）
    if (_mediaItemsEqual(_mediaItems, filteredItems) && _pendingSyncCount == pending) {
      return; // 没有变化，不需要更新
    }
    
    setState(() {
      _mediaItems = filteredItems;
      _pendingSyncCount = pending;
      _isLoading = false;
      _error = null;
    });
  }

  /// 排序媒体项
  List<MediaItem> _sortItems(List<MediaItem> items) {
    final sorted = List<MediaItem>.from(items);
    sorted.sort((a, b) {
      int result;
      switch (_sortBy) {
        case MediaSortBy.createdAt:
          result = a.createdAt.compareTo(b.createdAt);
          break;
        case MediaSortBy.modifiedAt:
          final aTime = a.modifiedAt ?? a.createdAt;
          final bTime = b.modifiedAt ?? b.createdAt;
          result = aTime.compareTo(bTime);
          break;
        case MediaSortBy.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case MediaSortBy.size:
          result = a.size.compareTo(b.size);
          break;
      }
      return _sortOrder == SortOrder.ascending ? result : -result;
    });
    return sorted;
  }

  /// 比较两个媒体列表是否相等
  bool _mediaItemsEqual(List<MediaItem> a, List<MediaItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      // 比较关键字段，而不是整个对象
      if (a[i].id != b[i].id ||
          a[i].syncStatus != b[i].syncStatus ||
          a[i].localPath != b[i].localPath ||
          a[i].thumbnailPath != b[i].thumbnailPath ||
          a[i].isStarred != b[i].isStarred) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadMedia() async {
    if (_libraryService == null) return;
    
    // 首次加载时显示 loading，之后的更新不显示
    if (_mediaItems.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final items = await _libraryService!.getMedia(_filter);
      
      // 计算待同步数量（远端文件未下载）
      final pending = items.where((item) => 
        item.syncStatus == SyncStatus.pending ||
        item.syncStatus == SyncStatus.failed
      ).length;
      
      setState(() {
        _mediaItems = items;
        _pendingSyncCount = pending;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 刷新并重新同步云端文件
  Future<void> _refreshWithSync() async {
    if (_libraryService == null) return;
    setState(() => _isLoading = true);

    try {
      // 如果已连接服务器，重新同步云端文件
      final apiService = _apiManager.getCurrentApiService();
      if (apiService != null) {
        final result = await apiService.getFileList();
        if (result['success'] == true) {
          final pictures = result['pictures'] as List<dynamic>? ?? [];
          final videos = result['videos'] as List<dynamic>? ?? [];
          final allFiles = <dynamic>[...pictures, ...videos];
          
          if (allFiles.isNotEmpty) {
            await _libraryService!.syncRemoteFiles(
              allFiles.cast(),
              baseUrl: apiService.baseUrl,
            );
          }
        }
      }
      
      // 重新加载媒体列表
      await _loadMedia();
    } catch (e) {
      setState(() {
        _error = '刷新失败: $e';
        _isLoading = false;
      });
    }
  }

  void _updateFilter() {
    _filter = MediaFilter(
      type: _typeFilter,
      isStarred: _starredOnly ? true : null,
      sortBy: _sortBy,
      sortOrder: _sortOrder,
    );
    _loadMedia();
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_mediaItems.map((m) => m.id));
    });
  }

  Future<void> _importFiles() async {
    if (_libraryService == null) return;
    
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.media,
    );

    if (result == null || result.files.isEmpty) return;

    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();

    if (paths.isEmpty) return;

    // 显示导入进度
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportProgressDialog(
        stream: _libraryService!.importFiles(paths),
        onComplete: () {
          Navigator.of(context).pop();
          _loadMedia();
        },
      ),
    );
  }

  Future<void> _importDirectory() async {
    if (_libraryService == null) return;
    
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;

    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportProgressDialog(
        stream: _libraryService!.importDirectory(result),
        onComplete: () {
          Navigator.of(context).pop();
          _loadMedia();
        },
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_libraryService == null) return;
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个项目吗？\n\n注意：这只会删除本地文件，远端文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _libraryService!.deleteMediaBatch(_selectedIds.toList());
    _toggleSelectionMode();
    _loadMedia();
  }

  Future<void> _toggleStarredSelected() async {
    if (_libraryService == null) return;
    if (_selectedIds.isEmpty) return;

    // 检查是否全部已星标
    final allStarred = _selectedIds.every((id) {
      final item = _mediaItems.firstWhere((m) => m.id == id);
      return item.isStarred;
    });

    await _libraryService!.setStarred(_selectedIds.toList(), !allStarred);
    _loadMedia();
  }

  void _openMediaDetail(MediaItem item) {
    // 云端文件（pending 状态）显示下载提示
    if (item.syncStatus == SyncStatus.pending) {
      _showDownloadDialog(item);
      return;
    }
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MediaDetailScreen(
          item: item,
          onUpdate: _loadMedia,
        ),
      ),
    );
  }

  /// 显示下载对话框
  void _showDownloadDialog(MediaItem item) {
    // 检查是否已连接服务器
    final apiService = _apiManager.getCurrentApiService();
    final isConnected = apiService != null;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('云端文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件名: ${item.name}'),
            const SizedBox(height: 8),
            Text('大小: ${item.formattedSize}'),
            const SizedBox(height: 16),
            Text(
              isConnected 
                  ? '点击下载按钮开始下载此文件。'
                  : '此文件存储在云端，需要连接到服务器后才能下载查看。',
              style: TextStyle(color: isConnected ? Colors.green : Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: isConnected
                ? () {
                    Navigator.of(context).pop();
                    _downloadRemoteFile(item, apiService);
                  }
                : null,
            icon: const Icon(Icons.cloud_download),
            label: const Text('下载'),
          ),
        ],
      ),
    );
  }

  /// 下载远端文件
  Future<void> _downloadRemoteFile(MediaItem item, dynamic apiService) async {
    if (item.sourceRef == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件路径无效')),
      );
      return;
    }

    // 显示下载进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(
        item: item,
        apiService: apiService,
        libraryService: _libraryService!,
        onComplete: (success, localPath) {
          Navigator.of(context).pop();
          if (success && localPath != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('下载完成: ${item.name}')),
            );
            _loadMedia();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('下载失败: ${item.name}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 统计信息栏
          _buildStatsBar(),
          // 筛选栏
          _buildFilterBar(),
          // 主体内容
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _selectionMode ? null : _buildFAB(),
    );
  }

  /// 统计信息栏
  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // 统计信息
          Text(
            '共 ${_mediaItems.length} 项',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          // 待同步数量
          if (_pendingSyncCount > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_pendingSyncCount 张待同步',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange[700],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _toggleSelectionMode,
        ),
        title: Text('已选择 ${_selectedIds.length} 项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _selectAll,
            tooltip: '全选',
          ),
          IconButton(
            icon: const Icon(Icons.star_outline),
            onPressed: _toggleStarredSelected,
            tooltip: '切换星标',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteSelected,
            tooltip: '删除',
          ),
        ],
      );
    }

    return AppBar(
      title: const Text('媒体库'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _showSearchDialog(),
          tooltip: '搜索',
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'import_files':
                _importFiles();
                break;
              case 'import_directory':
                _importDirectory();
                break;
              case 'refresh':
                _refreshWithSync();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'import_files',
              child: ListTile(
                leading: Icon(Icons.add_photo_alternate),
                title: Text('导入文件'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'import_directory',
              child: ListTile(
                leading: Icon(Icons.folder_open),
                title: Text('导入文件夹'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('刷新'),
                subtitle: _apiManager.getCurrentApiService() != null 
                    ? const Text('同步云端文件', style: TextStyle(fontSize: 12))
                    : null,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 第一行：类型筛选和星标
          Row(
            children: [
              // 类型筛选
              ChoiceChip(
                label: const Text('全部'),
                selected: _typeFilter == null,
                onSelected: (selected) {
                  setState(() => _typeFilter = null);
                  _updateFilter();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('照片'),
                selected: _typeFilter == MediaType.photo,
                onSelected: (selected) {
                  setState(() => _typeFilter = selected ? MediaType.photo : null);
                  _updateFilter();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('视频'),
                selected: _typeFilter == MediaType.video,
                onSelected: (selected) {
                  setState(() => _typeFilter = selected ? MediaType.video : null);
                  _updateFilter();
                },
              ),
              const Spacer(),
              // 星标筛选
              FilterChip(
                label: const Text('星标'),
                selected: _starredOnly,
                onSelected: (selected) {
                  setState(() => _starredOnly = selected);
                  _updateFilter();
                },
                avatar: Icon(
                  _starredOnly ? Icons.star : Icons.star_border,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：排序和分组
          Row(
            children: [
              // 排序按钮
              _buildSortButton(),
              const SizedBox(width: 8),
              // 分组按钮
              _buildGroupButton(),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建排序按钮
  Widget _buildSortButton() {
    String sortLabel;
    switch (_sortBy) {
      case MediaSortBy.createdAt:
        sortLabel = '时间';
        break;
      case MediaSortBy.modifiedAt:
        sortLabel = '修改时间';
        break;
      case MediaSortBy.name:
        sortLabel = '名称';
        break;
      case MediaSortBy.size:
        sortLabel = '大小';
        break;
    }

    return PopupMenuButton<MediaSortBy>(
      onSelected: (value) {
        setState(() {
          if (_sortBy == value) {
            // 点击相同的排序字段，切换排序方向
            _sortOrder = _sortOrder == SortOrder.ascending
                ? SortOrder.descending
                : SortOrder.ascending;
          } else {
            _sortBy = value;
            // 根据排序字段设置默认排序方向
            _sortOrder = value == MediaSortBy.name
                ? SortOrder.ascending
                : SortOrder.descending;
          }
        });
        _updateFilter();
      },
      itemBuilder: (context) => [
        _buildSortMenuItem(MediaSortBy.createdAt, '时间', Icons.access_time),
        _buildSortMenuItem(MediaSortBy.modifiedAt, '修改时间', Icons.update),
        _buildSortMenuItem(MediaSortBy.name, '名称', Icons.sort_by_alpha),
        _buildSortMenuItem(MediaSortBy.size, '大小', Icons.data_usage),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _sortOrder == SortOrder.ascending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              sortLabel,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<MediaSortBy> _buildSortMenuItem(
    MediaSortBy value,
    String label,
    IconData icon,
  ) {
    final isSelected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? Theme.of(context).primaryColor : null),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          if (isSelected)
            Icon(
              _sortOrder == SortOrder.ascending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 16,
              color: Theme.of(context).primaryColor,
            ),
        ],
      ),
    );
  }

  /// 构建分组按钮
  Widget _buildGroupButton() {
    String groupLabel;
    IconData groupIcon;
    switch (_groupMode) {
      case GroupMode.none:
        groupLabel = '不分组';
        groupIcon = Icons.grid_view;
        break;
      case GroupMode.byDay:
        groupLabel = '按天';
        groupIcon = Icons.calendar_today;
        break;
      case GroupMode.byMonth:
        groupLabel = '按月';
        groupIcon = Icons.calendar_month;
        break;
    }

    return PopupMenuButton<GroupMode>(
      onSelected: (value) {
        setState(() => _groupMode = value);
      },
      itemBuilder: (context) => [
        _buildGroupMenuItem(GroupMode.none, '不分组', Icons.grid_view),
        _buildGroupMenuItem(GroupMode.byDay, '按天分组', Icons.calendar_today),
        _buildGroupMenuItem(GroupMode.byMonth, '按月分组', Icons.calendar_month),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(groupIcon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              groupLabel,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<GroupMode> _buildGroupMenuItem(
    GroupMode value,
    String label,
    IconData icon,
  ) {
    final isSelected = _groupMode == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? Theme.of(context).primaryColor : null),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          if (isSelected)
            Icon(Icons.check, size: 16, color: Theme.of(context).primaryColor),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMedia,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_mediaItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '媒体库为空',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '使用手机相机拍摄或点击右下角按钮导入',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    // 根据分组模式选择不同的显示方式
    if (_groupMode == GroupMode.none) {
      return _buildFlatGrid();
    } else {
      return _buildGroupedGrid();
    }
  }

  /// 构建平铺网格（不分组）
  Widget _buildFlatGrid() {
    return RefreshIndicator(
      onRefresh: _refreshWithSync,
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: _mediaItems.length,
        itemBuilder: (context, index) {
          final item = _mediaItems[index];
          return MediaGridItem(
            key: ValueKey(item.id),
            item: item,
            isSelected: _selectedIds.contains(item.id),
            selectionMode: _selectionMode,
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(item.id);
              } else {
                _openMediaDetail(item);
              }
            },
            onLongPress: () {
              if (!_selectionMode) {
                _toggleSelectionMode();
                _toggleSelection(item.id);
              }
            },
          );
        },
      ),
    );
  }

  /// 构建分组网格
  Widget _buildGroupedGrid() {
    // 按日期分组
    final groups = _groupMediaItems(_mediaItems);
    
    return RefreshIndicator(
      onRefresh: _refreshWithSync,
      child: CustomScrollView(
        slivers: [
          for (final entry in groups.entries) ...[
            // 分组标题
            SliverToBoxAdapter(
              child: _buildGroupHeader(entry.key, entry.value.length),
            ),
            // 分组内容
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = entry.value[index];
                    return MediaGridItem(
                      key: ValueKey(item.id),
                      item: item,
                      isSelected: _selectedIds.contains(item.id),
                      selectionMode: _selectionMode,
                      onTap: () {
                        if (_selectionMode) {
                          _toggleSelection(item.id);
                        } else {
                          _openMediaDetail(item);
                        }
                      },
                      onLongPress: () {
                        if (!_selectionMode) {
                          _toggleSelectionMode();
                          _toggleSelection(item.id);
                        }
                      },
                    );
                  },
                  childCount: entry.value.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ],
      ),
    );
  }

  /// 分组媒体项
  Map<String, List<MediaItem>> _groupMediaItems(List<MediaItem> items) {
    final Map<String, List<MediaItem>> groups = {};
    
    for (final item in items) {
      final key = _getGroupKey(item.createdAt);
      groups.putIfAbsent(key, () => []).add(item);
    }
    
    return groups;
  }

  /// 获取分组键
  String _getGroupKey(DateTime date) {
    switch (_groupMode) {
      case GroupMode.none:
        return '';
      case GroupMode.byDay:
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case GroupMode.byMonth:
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
  }

  /// 构建分组标题
  Widget _buildGroupHeader(String groupKey, int count) {
    String displayText;
    
    if (_groupMode == GroupMode.byDay) {
      // 解析日期
      final parts = groupKey.split('-');
      if (parts.length == 3) {
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final dateOnly = DateTime(date.year, date.month, date.day);
        
        if (dateOnly == today) {
          displayText = '今天';
        } else if (dateOnly == yesterday) {
          displayText = '昨天';
        } else if (date.year == now.year) {
          displayText = '${date.month}月${date.day}日';
        } else {
          displayText = '${date.year}年${date.month}月${date.day}日';
        }
      } else {
        displayText = groupKey;
      }
    } else if (_groupMode == GroupMode.byMonth) {
      final parts = groupKey.split('-');
      if (parts.length == 2) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final now = DateTime.now();
        
        if (year == now.year && month == now.month) {
          displayText = '本月';
        } else if (year == now.year) {
          displayText = '$month月';
        } else {
          displayText = '$year年$month月';
        }
      } else {
        displayText = groupKey;
      }
    } else {
      displayText = groupKey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            displayText,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count 项',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: _importFiles,
      tooltip: '导入媒体',
      child: const Icon(Icons.add),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => _SearchDialog(
        onSearch: (query) {
          setState(() {
            _filter = _filter.copyWith(searchQuery: query);
          });
          _loadMedia();
        },
      ),
    );
  }
}

/// 导入进度对话框
class _ImportProgressDialog extends StatefulWidget {
  final Stream<ImportProgress> stream;
  final VoidCallback onComplete;

  const _ImportProgressDialog({
    required this.stream,
    required this.onComplete,
  });

  @override
  State<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<_ImportProgressDialog> {
  ImportProgress? _progress;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    widget.stream.listen(
      (progress) {
        setState(() => _progress = progress);
      },
      onDone: () {
        setState(() => _completed = true);
        Future.delayed(const Duration(milliseconds: 500), widget.onComplete);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_completed ? '导入完成' : '正在导入...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_progress != null) ...[
            LinearProgressIndicator(value: _progress!.progress),
            const SizedBox(height: 16),
            Text('${_progress!.completed} / ${_progress!.total}'),
            if (_progress!.currentFile != null) ...[
              const SizedBox(height: 8),
              Text(
                _progress!.currentFile!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_progress!.failed > 0) ...[
              const SizedBox(height: 8),
              Text(
                '失败: ${_progress!.failed}',
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ] else
            const CircularProgressIndicator(),
        ],
      ),
    );
  }
}

/// 搜索对话框
class _SearchDialog extends StatefulWidget {
  final Function(String) onSearch;

  const _SearchDialog({required this.onSearch});

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('搜索'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '输入文件名关键词',
          prefixIcon: Icon(Icons.search),
        ),
        onSubmitted: (value) {
          widget.onSearch(value);
          Navigator.of(context).pop();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onSearch(_controller.text);
            Navigator.of(context).pop();
          },
          child: const Text('搜索'),
        ),
      ],
    );
  }
}

/// 下载进度对话框
class _DownloadProgressDialog extends StatefulWidget {
  final MediaItem item;
  final dynamic apiService;
  final MediaLibraryService libraryService;
  final Function(bool success, String? localPath) onComplete;

  const _DownloadProgressDialog({
    required this.item,
    required this.apiService,
    required this.libraryService,
    required this.onComplete,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String _status = '准备下载...';
  bool _downloading = false;
  bool _completed = false;
  DownloadManager? _downloadManager;
  String? _taskId;
  StreamSubscription? _tasksSubscription;
  StreamSubscription? _completionSubscription;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    _completionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _cancelDownload() async {
    if (_downloadManager != null && _taskId != null) {
      await _downloadManager!.cancelDownload(_taskId!);
    }
    if (mounted) {
      widget.onComplete(false, null);
    }
  }

  Future<void> _startDownload() async {
    if (_downloading) return;
    _downloading = true;

    try {
      final remotePath = widget.item.sourceRef!;
      final baseUrl = widget.apiService.baseUrl;
      
      // 创建下载管理器
      _downloadManager = DownloadManager(baseUrl: baseUrl);
      await _downloadManager!.initialize();
      
      if (!mounted) return;
      setState(() => _status = '开始下载...');
      
      // 添加下载任务（返回任务ID）
      _taskId = await _downloadManager!.addDownload(
        remoteFilePath: remotePath,
        fileName: widget.item.name,
      );
      
      // 监听下载进度
      _tasksSubscription = _downloadManager!.tasksStream.listen((tasks) {
        final currentTask = tasks.where((t) => t.id == _taskId).firstOrNull;
        if (currentTask != null && mounted && !_completed) {
          setState(() {
            if (currentTask.totalBytes > 0) {
              _progress = currentTask.downloadedBytes / currentTask.totalBytes;
              _status = '下载中: ${(currentTask.downloadedBytes / 1024 / 1024).toStringAsFixed(1)} / ${(currentTask.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB';
            } else {
              _status = '下载中: ${(currentTask.downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB';
            }
            
            // 检查是否失败
            if (currentTask.status == DownloadStatus.failed) {
              _status = '下载失败: ${currentTask.errorMessage ?? "未知错误"}';
            }
          });
        }
      });
      
      // 监听下载完成
      _completionSubscription = _downloadManager!.completionStream.listen((completedTask) async {
        if (completedTask.id == _taskId && mounted && !_completed) {
          _completed = true;
          
          if (completedTask.status == DownloadStatus.completed) {
            // 更新媒体库记录
            await widget.libraryService.markAsDownloaded(
              widget.item.id,
              completedTask.localFilePath,
            );
            widget.onComplete(true, completedTask.localFilePath);
          } else {
            // 下载失败
            widget.onComplete(false, null);
          }
        }
      });
      
    } catch (e) {
      if (mounted) {
        setState(() => _status = '下载失败: $e');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_completed) {
            _completed = true;
            widget.onComplete(false, null);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('下载: ${widget.item.name}', overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          const SizedBox(height: 16),
          Text(_status),
          const SizedBox(height: 8),
          Text(
            '${(_progress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancelDownload,
          child: const Text('取消'),
        ),
      ],
    );
  }
}
