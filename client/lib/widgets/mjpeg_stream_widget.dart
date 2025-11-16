import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import '../services/logger_service.dart';

/// 使用flutter_mjpeg库显示MJPEG流的Widget
/// 注意：此组件直接填充父容器，宽高比由外层的 AspectRatio 控制
class MjpegStreamWidget extends StatefulWidget {
  final String streamUrl;
  final int? previewWidth; // 预览流的实际宽度（从服务器获取，仅用于日志）
  final int? previewHeight; // 预览流的实际高度（从服务器获取，仅用于日志）

  const MjpegStreamWidget({
    Key? key,
    required this.streamUrl,
    this.previewWidth,
    this.previewHeight,
  }) : super(key: key);

  @override
  State<MjpegStreamWidget> createState() => _MjpegStreamWidgetState();
}

class _MjpegStreamWidgetState extends State<MjpegStreamWidget> {
  final ClientLoggerService _logger = ClientLoggerService();
  bool _hasError = false;
  String? _errorMessage;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  @override
  void initState() {
    super.initState();
    _logger.log('初始化MJPEG流: ${widget.streamUrl}', tag: 'PREVIEW');
    // 记录初始预览尺寸（如果提供）
    if (widget.previewWidth != null && widget.previewHeight != null) {
      _logger.log(
          'MjpegStreamWidget使用服务器预览尺寸: ${widget.previewWidth}x${widget.previewHeight}',
          tag: 'PREVIEW');
    }
  }

  @override
  void didUpdateWidget(MjpegStreamWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在预览尺寸变化时记录日志
    if (widget.previewWidth != oldWidget.previewWidth ||
        widget.previewHeight != oldWidget.previewHeight) {
      if (widget.previewWidth != null && widget.previewHeight != null) {
        _logger.log(
            'MjpegStreamWidget预览尺寸已更新: ${widget.previewWidth}x${widget.previewHeight}',
            tag: 'PREVIEW');
      }
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    super.dispose();
  }

  void _onError(String error) {
    _logger.logError('MJPEG流错误', error: Exception(error));
    if (!mounted) return;

    // 使用addPostFrameCallback确保不在build期间调用setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 只有非超时错误才触发重连（超时可能是正常的）
      final isTimeout = error.contains('Timeout') || error.contains('超时');

      setState(() {
        _hasError = true;
        _errorMessage = error;
      });

      // 自动重连（超时错误也重连，但延迟更短）
      if (!isTimeout || _reconnectAttempts < 3) {
        _scheduleReconnect();
      } else {
        _logger.log('超时错误，暂停重连', tag: 'PREVIEW');
      }
    });
  }

  // 安排重连
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.log('达到最大重连次数，停止重连', tag: 'PREVIEW');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    _logger.log('安排重连MJPEG流 (第$_reconnectAttempts次)', tag: 'PREVIEW');

    _reconnectTimer = Timer(Duration(seconds: 3 * _reconnectAttempts), () {
      if (mounted) {
        _logger.log('执行重连MJPEG流 (第$_reconnectAttempts次)', tag: 'PREVIEW');
        setState(() {
          _hasError = false;
          _errorMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 如果达到最大重连次数，显示错误信息
    if (_hasError && _reconnectAttempts >= _maxReconnectAttempts) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.videocam_off,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            '预览加载失败',
            style: TextStyle(color: Colors.white),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      );
    }

    // 如果有错误但还在重连中，只显示加载指示器
    if (_hasError && _reconnectTimer != null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 如果错误但没有重连定时器，说明可能是临时错误，直接尝试重建
    if (_hasError && _reconnectTimer == null) {
      // 重置错误状态，让流重新连接
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _hasError = false;
            _errorMessage = null;
            _reconnectAttempts = 0;
          });
        }
      });
    }

    // 直接填充父容器，使用FittedBox确保视频填充整个容器
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用contain避免裁剪，保持完整画面
        final previewWidth = widget.previewWidth?.toDouble() ?? 640;
        final previewHeight = widget.previewHeight?.toDouble() ?? 480;
        
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
              child: Mjpeg(
                key: ValueKey('mjpeg_$_reconnectAttempts'), // 使用key强制重建以重连
                isLive: true,
                stream: widget.streamUrl,
                error: (context, error, stack) {
                  _logger.logError('MJPEG流错误', error: error, stackTrace: stack);
                  // 延迟调用_onError，避免在build期间调用setState
                  Future.microtask(() => _onError(error.toString()));
                  return const Center(
                    child: Icon(
                      Icons.videocam_off,
                      size: 64,
                      color: Colors.grey,
                    ),
                  );
                },
                loading: (context) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
