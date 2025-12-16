import 'package:flutter/material.dart';
import 'library/library_screen.dart';
import 'capture/source_selector_screen.dart';
import 'client_settings_screen.dart';
import '../core/core.dart';
import '../services/logger_service.dart';

/// 工具箱首页
///
/// 提供各功能模块的独立入口
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ClientLoggerService _logger = ClientLoggerService();
  late final MediaLibraryService _libraryService;

  bool _isInitialized = false;
  int _photoCount = 0;
  int _videoCount = 0;
  int _starredCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      _logger.log('初始化媒体库服务...', tag: 'HOME');

      _libraryService = MediaLibraryService.instance;
      await _libraryService.init();

      await _loadStats();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      _logger.log('媒体库服务初始化完成', tag: 'HOME');
    } catch (e, stackTrace) {
      _logger.logError('初始化媒体库服务失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isInitialized = true; // 即使失败也显示界面
        });
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      final allMedia = await _libraryService.getMedia(MediaFilter.defaultFilter);
      final starredMedia = await _libraryService.getMedia(
        const MediaFilter(isStarred: true),
      );

      if (mounted) {
        setState(() {
          _photoCount = allMedia.where((m) => m.type == MediaType.photo).length;
          _videoCount = allMedia.where((m) => m.type == MediaType.video).length;
          _starredCount = starredMedia.length;
        });
      }
    } catch (e) {
      _logger.logError('加载统计信息失败', error: e);
    }
  }

  void _openCamera() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SourceSelectorScreen(),
      ),
    ).then((_) => _loadStats()); // 返回时刷新统计
  }

  void _openLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LibraryScreen(libraryService: _libraryService),
      ),
    ).then((_) => _loadStats());
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ClientSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在初始化...',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('作业拍摄助手'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 工具入口
              Expanded(
                child: _buildToolGrid(),
              ),

              const SizedBox(height: 24),

              // 快捷信息
              _buildStatsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolGrid() {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.2,
      shrinkWrap: true,
      children: [
        _buildToolCard(
          icon: Icons.camera_alt,
          label: '拍摄',
          subtitle: '本机或手机相机',
          color: Colors.blue,
          onTap: _openCamera,
        ),
        _buildToolCard(
          icon: Icons.photo_library,
          label: '媒体库',
          subtitle: '$_photoCount 照片, $_videoCount 视频',
          color: Colors.green,
          onTap: _openLibrary,
        ),
        _buildToolCard(
          icon: Icons.settings,
          label: '设置',
          subtitle: '应用配置',
          color: Colors.grey,
          onTap: _openSettings,
        ),
        _buildToolCard(
          icon: Icons.task_alt,
          label: '任务',
          subtitle: '开发中',
          color: Colors.orange,
          enabled: false,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildToolCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Card(
      elevation: enabled ? 2 : 0,
      color: enabled ? null : Colors.grey[200],
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: enabled ? color : Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: enabled ? null : Colors.grey[500],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? Colors.grey[600] : Colors.grey[400],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快捷信息',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.photo,
                  label: '照片',
                  value: '$_photoCount',
                ),
                const SizedBox(width: 24),
                _buildStatItem(
                  icon: Icons.videocam,
                  label: '视频',
                  value: '$_videoCount',
                ),
                const SizedBox(width: 24),
                _buildStatItem(
                  icon: Icons.star,
                  label: '已星标',
                  value: '$_starredCount',
                  color: Colors.amber,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}
