import 'dart:async';
import 'package:flutter/services.dart';
import 'logger_service.dart';

/// 设备方向监听服务 - 监听设备方向变化
class OrientationService {
  static const EventChannel _eventChannel = EventChannel('com.firoyang.helloknightrcc_server/orientation');
  
  final LoggerService _logger = LoggerService();
  StreamSubscription<int>? _orientationSubscription;
  
  // 方向变化回调函数
  Function(int)? onOrientationChanged;
  
  /// 开始监听设备方向变化
  void startListening() {
    if (_orientationSubscription != null) {
      _logger.log('方向监听已启动，跳过重复启动', tag: 'ORIENTATION');
      return;
    }
    
    try {
      _orientationSubscription = _eventChannel
          .receiveBroadcastStream()
          .cast<int>()
          .listen(
            (orientation) {
              _logger.log('收到设备方向变化: $orientation 度', tag: 'ORIENTATION');
              onOrientationChanged?.call(orientation);
            },
            onError: (error) {
              _logger.logError('方向监听错误', error: error);
            },
          );
      _logger.log('方向监听已启动', tag: 'ORIENTATION');
    } catch (e) {
      _logger.logError('启动方向监听失败', error: e);
    }
  }
  
  /// 停止监听设备方向变化
  void stopListening() {
    _orientationSubscription?.cancel();
    _orientationSubscription = null;
    _logger.log('方向监听已停止', tag: 'ORIENTATION');
  }
  
  /// 释放资源
  void dispose() {
    stopListening();
  }
}


