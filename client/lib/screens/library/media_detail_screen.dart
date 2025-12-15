import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../../core/media/media.dart';

/// 媒体详情页面
class MediaDetailScreen extends StatefulWidget {
  final MediaItem item;
  final VoidCallback? onUpdate;

  const MediaDetailScreen({
    super.key,
    required this.item,
    this.onUpdate,
  });

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  final MediaLibraryService _libraryService = MediaLibraryService.instance;
  late MediaItem _item;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  Future<void> _toggleStarred() async {
    await _libraryService.toggleStarred(_item.id);
    final updated = await _libraryService.getMediaById(_item.id);
    if (updated != null) {
      setState(() => _item = updated);
      widget.onUpdate?.call();
    }
  }

  Future<void> _deleteItem() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个媒体文件吗？'),
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

    await _libraryService.deleteMedia(_item.id);
    widget.onUpdate?.call();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _openFile() {
    OpenFile.open(_item.localPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_item.name),
        actions: [
          IconButton(
            icon: Icon(
              _item.isStarred ? Icons.star : Icons.star_border,
              color: _item.isStarred ? Colors.amber : Colors.white,
            ),
            onPressed: _toggleStarred,
            tooltip: _item.isStarred ? '取消星标' : '添加星标',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _openFile,
            tooltip: '打开文件',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoSheet(),
            tooltip: '详细信息',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteItem,
            tooltip: '删除',
          ),
        ],
      ),
      body: Center(
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_item.type == MediaType.photo) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(
          File(_item.localPath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildError(),
        ),
      );
    } else {
      // 视频显示缩略图和播放按钮
      return GestureDetector(
        onTap: _openFile,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_item.thumbnailPath != null)
              Image.file(
                File(_item.thumbnailPath!),
                fit: BoxFit.contain,
              )
            else
              Container(
                color: Colors.grey[900],
                child: const Icon(
                  Icons.videocam,
                  size: 100,
                  color: Colors.grey,
                ),
              ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                size: 50,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image, size: 64, color: Colors.grey[600]),
        const SizedBox(height: 16),
        Text(
          '无法加载图片',
          style: TextStyle(color: Colors.grey[400]),
        ),
      ],
    );
  }

  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _InfoSheet(item: _item),
    );
  }
}

/// 信息面板
class _InfoSheet extends StatelessWidget {
  final MediaItem item;

  const _InfoSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '详细信息',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _buildInfoRow('文件名', item.name),
          _buildInfoRow('类型', item.type.displayName),
          _buildInfoRow('大小', item.formattedSize),
          _buildInfoRow('创建时间', _formatDateTime(item.createdAt)),
          if (item.modifiedAt != null)
            _buildInfoRow('修改时间', _formatDateTime(item.modifiedAt!)),
          _buildInfoRow('路径', item.localPath),
          if (item.metadata != null) ...[
            if (item.metadata!.resolution != null)
              _buildInfoRow('分辨率', item.metadata!.resolution!),
            if (item.metadata!.formattedDuration != null)
              _buildInfoRow('时长', item.metadata!.formattedDuration!),
          ],
          if (item.sourceId != null)
            _buildInfoRow('来源', item.sourceId!),
          if (item.tags.isNotEmpty)
            _buildInfoRow('标签', item.tags.join(', ')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
