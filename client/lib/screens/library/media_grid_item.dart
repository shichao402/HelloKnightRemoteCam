import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/media/models/media_item.dart';
import '../../core/media/models/media_type.dart';

/// 媒体网格项组件
/// 支持显示同步状态（Google Photos 风格）
/// 统一使用本地缩略图（由 ThumbnailService 管理）
class MediaGridItem extends StatelessWidget {
  final MediaItem item;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onStarToggle;

  const MediaGridItem({
    super.key,
    required this.item,
    this.isSelected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onStarToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 缩略图
          _buildThumbnail(),

          // 视频时长标识
          if (item.type == MediaType.video) _buildVideoBadge(),

          // 同步状态标识（云端/下载中）
          if (!selectionMode) _buildSyncStatusBadge(),

          // 选中状态
          if (selectionMode) _buildSelectionOverlay(),

          // 星标
          if (item.isStarred && !selectionMode) _buildStarBadge(),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    // 优先使用已持久化的缩略图（无论是云端下载的还是本地生成的）
    if (item.thumbnailPath != null && item.thumbnailPath!.isNotEmpty) {
      final file = File(item.thumbnailPath!);
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 256, // 限制解码尺寸，节省内存
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    // 云端文件但缩略图还没下载完成
    if (item.syncStatus == SyncStatus.pending && item.localPath.isEmpty) {
      return _buildCloudPlaceholder();
    }

    // 本地文件但缩略图还没生成，尝试直接显示图片
    if (item.type == MediaType.photo && item.localPath.isNotEmpty) {
      final file = File(item.localPath);
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 256,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  /// 云端文件占位符（缩略图加载中或失败）
  Widget _buildCloudPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_queue,
            size: 32,
            color: Colors.blue[300],
          ),
          const SizedBox(height: 4),
          Text(
            '云端',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        item.type == MediaType.video ? Icons.videocam : Icons.image,
        size: 48,
        color: Colors.grey[600],
      ),
    );
  }

  Widget _buildVideoBadge() {
    return Positioned(
      right: 4,
      bottom: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, size: 14, color: Colors.white),
            if (item.metadata?.formattedDuration != null) ...[
              const SizedBox(width: 2),
              Text(
                item.metadata!.formattedDuration!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.3) : Colors.transparent,
          border: isSelected
              ? Border.all(color: Colors.blue, width: 3)
              : null,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.blue : Colors.white.withValues(alpha: 0.8),
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.grey,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStarBadge() {
    return Positioned(
      left: 4,
      top: 4,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.star,
          size: 16,
          color: Colors.amber,
        ),
      ),
    );
  }

  /// 同步状态标识（Google Photos 风格）
  Widget _buildSyncStatusBadge() {
    // 只有非本地状态才显示标识
    if (item.syncStatus == SyncStatus.local || 
        item.syncStatus == SyncStatus.synced) {
      return const SizedBox.shrink();
    }

    IconData icon;
    Color color;
    
    switch (item.syncStatus) {
      case SyncStatus.pending:
        // 云端未下载 - 显示云朵图标
        icon = Icons.cloud_outlined;
        color = Colors.white;
        break;
      case SyncStatus.failed:
        // 同步失败 - 显示警告图标
        icon = Icons.cloud_off;
        color = Colors.orange;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Positioned(
      right: 4,
      top: 4,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 14,
          color: color,
        ),
      ),
    );
  }
}
