import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/media/models/media_item.dart';
import '../../core/media/models/media_type.dart';

/// 媒体网格项组件
/// 支持显示同步状态（Google Photos 风格）
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
    if (item.thumbnailPath != null) {
      final file = File(item.thumbnailPath!);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    // 尝试直接显示图片（如果是图片类型）
    if (item.type == MediaType.photo) {
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
          color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.transparent,
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
                color: isSelected ? Colors.blue : Colors.white.withOpacity(0.8),
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
