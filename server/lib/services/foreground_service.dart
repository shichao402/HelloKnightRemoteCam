import 'package:flutter/services.dart';
import 'logger_service.dart';

/// 前台服务控制 - 用于保持应用在后台运行时继续工作
class ForegroundService {
  static const MethodChannel _channel = MethodChannel('com.firoyang.helloknightrcc_server/foreground_service');
  final LoggerService _logger = LoggerService();

  /// 启动前台服务
  Future<void> start() async {
    try {
      _logger.log('启动前台服务', tag: 'FOREGROUND_SERVICE');
      await _channel.invokeMethod('startForegroundService');
      _logger.log('前台服务已启动', tag: 'FOREGROUND_SERVICE');
    } catch (e, stackTrace) {
      _logger.logError('启动前台服务失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 停止前台服务
  Future<void> stop() async {
    try {
      _logger.log('停止前台服务', tag: 'FOREGROUND_SERVICE');
      await _channel.invokeMethod('stopForegroundService');
      _logger.log('前台服务已停止', tag: 'FOREGROUND_SERVICE');
    } catch (e, stackTrace) {
      _logger.logError('停止前台服务失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 检查是否已忽略电池优化
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (e, stackTrace) {
      _logger.logError('检查电池优化状态失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 请求忽略电池优化
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      _logger.log('请求忽略电池优化', tag: 'FOREGROUND_SERVICE');
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      _logger.log('已请求忽略电池优化', tag: 'FOREGROUND_SERVICE');
    } catch (e, stackTrace) {
      _logger.logError('请求忽略电池优化失败', error: e, stackTrace: stackTrace);
    }
  }
}

