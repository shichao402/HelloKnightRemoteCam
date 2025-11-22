import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import '../services/update_service.dart';
import '../services/logger_service.dart';

/// 统一的更新对话框组件
/// 所有更新相关的UI都使用这个组件
class UpdateDialog extends StatefulWidget {
  final UpdateService updateService;
  final UpdateInfo updateInfo;
  final ClientLoggerService logger;

  const UpdateDialog({
    super.key,
    required this.updateService,
    required this.updateInfo,
    required this.logger,
  });

  /// 显示更新对话框的便捷方法
  static void show(
    BuildContext context, {
    required UpdateService updateService,
    required UpdateInfo updateInfo,
    required ClientLoggerService logger,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) => UpdateDialog(
        updateService: updateService,
        updateInfo: updateInfo,
        logger: logger,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _statusMessage; // 当前操作状态提示

  /// 将技术性错误转换为友好的中文提示
  String _getFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // 404错误 - 文件不存在
    if (errorString.contains('404') || errorString.contains('not found')) {
      return '下载失败：更新文件不存在，请稍后重试或联系开发者';
    }
    
    // 网络连接错误
    if (errorString.contains('network') || 
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('socket') ||
        errorString.contains('failed host lookup')) {
      return '下载失败：网络连接异常，请检查网络设置后重试';
    }
    
    // 权限错误
    if (errorString.contains('permission') || 
        errorString.contains('denied') ||
        errorString.contains('unauthorized')) {
      return '下载失败：存储权限不足，请在设置中授予存储权限';
    }
    
    // 磁盘空间不足
    if (errorString.contains('space') || 
        errorString.contains('disk') ||
        errorString.contains('storage')) {
      return '下载失败：存储空间不足，请清理空间后重试';
    }
    
    // 文件路径相关错误
    if (errorString.contains('path') || 
        errorString.contains('file') ||
        errorString.contains('directory')) {
      return '下载失败：无法保存文件，请检查存储权限';
    }
    
    // 服务器错误
    if (errorString.contains('500') || 
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('server error')) {
      return '下载失败：服务器暂时不可用，请稍后重试';
    }
    
    // 其他错误 - 显示简化后的错误信息
    if (errorString.contains('dioexception')) {
      if (errorString.contains('bad response')) {
        return '下载失败：服务器响应异常，请稍后重试';
      }
      return '下载失败：网络请求异常，请检查网络连接';
    }
    
    // 默认错误提示
    return '下载失败：请检查网络连接后重试，如问题持续存在请联系开发者';
  }

  Future<void> _downloadAndOpen() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    try {
      widget.logger.log('开始下载更新文件', tag: 'UPDATE');
      
      final filePath = await widget.updateService.downloadUpdateFile(
        widget.updateInfo,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
              // 有进度时清除状态消息
              if (_statusMessage != null && total > 0) {
                _statusMessage = null;
              }
            });
          }
        },
        onStatus: (status) {
          if (mounted) {
            setState(() {
              _statusMessage = status;
            });
          }
        },
      );

      if (filePath == null) {
        throw Exception('下载失败：文件路径为空');
      }

      widget.logger.log('下载完成，打开文件: $filePath', tag: 'UPDATE');
      
      // 关闭对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 打开文件
      final success = await widget.updateService.openDownloadedFile(filePath);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('下载完成，但无法打开文件'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stackTrace) {
      widget.logger.logError('下载更新文件失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = _getFriendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本: ${widget.updateInfo.version}'),
            const SizedBox(height: 8),
            if (widget.updateInfo.releaseNotes != null) ...[
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.updateInfo.releaseNotes!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '文件: ${widget.updateInfo.fileName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              // 显示状态消息（如果有）
              if (_statusMessage != null) ...[
                Text(
                  _statusMessage!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
              ] else ...[
                const Text('正在下载...', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              if (_totalBytes > 0)
                LinearProgressIndicator(
                  value: _downloadedBytes / _totalBytes,
                )
              else if (_statusMessage != null)
                const LinearProgressIndicator(), // 不确定进度时显示无限进度条
              if (_totalBytes > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${(_downloadedBytes / _totalBytes * 100).toStringAsFixed(1)}% '
                  '(${(_downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB / '
                  '${(_totalBytes / 1024 / 1024).toStringAsFixed(2)} MB)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.logger.log('用户取消更新', tag: 'UPDATE');
            },
            child: const Text('取消'),
          ),
        ElevatedButton(
          onPressed: _isDownloading ? null : _downloadAndOpen,
          child: Text(_isDownloading ? '下载中...' : '立即下载'),
        ),
      ],
    );
  }
}

