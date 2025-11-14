import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import '../services/logger_service.dart';

/// 使用flutter_mjpeg库显示MJPEG流的Widget
class MjpegStreamWidget extends StatefulWidget {
  final String streamUrl;
  final BoxFit fit;

  const MjpegStreamWidget({
    Key? key,
    required this.streamUrl,
    this.fit = BoxFit.contain,
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
          const SizedBox(height: 8),
          Text(
            '已尝试重连 $_reconnectAttempts 次',
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
        ],
      );
    }

    // 如果有错误但还在重连中，显示重连状态
    if (_hasError && _reconnectTimer != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '预览流断开，正在重连... ($_reconnectAttempts/$_maxReconnectAttempts)',
            style: const TextStyle(color: Colors.white),
          ),
        ],
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

    return Mjpeg(
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
    );
  }
}
