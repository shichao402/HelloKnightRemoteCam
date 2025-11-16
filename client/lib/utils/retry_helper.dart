import 'dart:async';
import 'package:flutter/material.dart';
import '../services/logger_service.dart';

/// 重试助手 - 使用回调+超时保护的方式处理重试逻辑
class RetryHelper {
  final ClientLoggerService _logger = ClientLoggerService();
  
  Timer? _timer;
  int _attempts = 0;
  bool _isRunning = false;
  bool _isCancelled = false;
  
  /// 执行带重试的操作
  /// 
  /// [operation] 要执行的操作，返回 Future<bool>，true表示成功，false表示需要重试
  /// [onSuccess] 成功回调
  /// [onFailure] 失败回调（达到最大重试次数后调用）
  /// [maxAttempts] 最大重试次数
  /// [interval] 重试间隔
  /// [timeout] 每次操作的超时时间
  /// [tag] 日志标签
  Future<void> executeWithRetry({
    required Future<bool> Function() operation,
    required VoidCallback onSuccess,
    required VoidCallback onFailure,
    int maxAttempts = 20,
    Duration interval = const Duration(seconds: 3),
    Duration? timeout,
    String tag = 'RETRY',
  }) async {
    if (_isRunning) {
      _logger.log('重试操作已在运行中，跳过', tag: tag);
      return;
    }
    
    _isRunning = true;
    _isCancelled = false;
    _attempts = 0;
    
    _executeOperation(
      operation: operation,
      onSuccess: onSuccess,
      onFailure: onFailure,
      maxAttempts: maxAttempts,
      interval: interval,
      timeout: timeout,
      tag: tag,
    );
  }
  
  void _executeOperation({
    required Future<bool> Function() operation,
    required VoidCallback onSuccess,
    required VoidCallback onFailure,
    required int maxAttempts,
    required Duration interval,
    Duration? timeout,
    required String tag,
  }) async {
    if (_isCancelled) {
      _isRunning = false;
      return;
    }
    
    _attempts++;
    _logger.log('执行操作 (第$_attempts次)', tag: tag);
    
    try {
      Future<bool> operationFuture = operation();
      
      // 如果设置了超时，使用超时保护
      if (timeout != null) {
        operationFuture = operationFuture.timeout(
          timeout,
          onTimeout: () {
            _logger.log('操作超时 (第$_attempts次)', tag: tag);
            return false;
          },
        );
      }
      
      final success = await operationFuture;
      
      if (_isCancelled) {
        _isRunning = false;
        return;
      }
      
      if (success) {
        _logger.log('操作成功 (第$_attempts次)', tag: tag);
        _isRunning = false;
        _attempts = 0;
        onSuccess();
        return;
      }
      
      // 操作失败，检查是否达到最大重试次数
      if (_attempts >= maxAttempts) {
        _logger.log('达到最大重试次数 ($maxAttempts)，停止重试', tag: tag);
        _isRunning = false;
        _attempts = 0;
        onFailure();
        return;
      }
      
      // 安排下一次重试
      _scheduleNextRetry(
        operation: operation,
        onSuccess: onSuccess,
        onFailure: onFailure,
        maxAttempts: maxAttempts,
        interval: interval,
        timeout: timeout,
        tag: tag,
      );
    } catch (e, stackTrace) {
      if (_isCancelled) {
        _isRunning = false;
        return;
      }
      
      _logger.logError('操作执行失败 (第$_attempts次)', error: e, stackTrace: stackTrace);
      
      // 检查是否达到最大重试次数
      if (_attempts >= maxAttempts) {
        _logger.log('达到最大重试次数 ($maxAttempts)，停止重试', tag: tag);
        _isRunning = false;
        _attempts = 0;
        onFailure();
        return;
      }
      
      // 安排下一次重试
      _scheduleNextRetry(
        operation: operation,
        onSuccess: onSuccess,
        onFailure: onFailure,
        maxAttempts: maxAttempts,
        interval: interval,
        timeout: timeout,
        tag: tag,
      );
    }
  }
  
  void _scheduleNextRetry({
    required Future<bool> Function() operation,
    required VoidCallback onSuccess,
    required VoidCallback onFailure,
    required int maxAttempts,
    required Duration interval,
    Duration? timeout,
    required String tag,
  }) {
    _timer?.cancel();
    _timer = Timer(interval, () {
      if (!_isCancelled) {
        _executeOperation(
          operation: operation,
          onSuccess: onSuccess,
          onFailure: onFailure,
          maxAttempts: maxAttempts,
          interval: interval,
          timeout: timeout,
          tag: tag,
        );
      }
    });
  }
  
  /// 取消重试
  void cancel() {
    if (!_isRunning) return;
    
    _isCancelled = true;
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _attempts = 0;
  }
  
  /// 检查是否正在运行
  bool get isRunning => _isRunning;
  
  /// 获取当前重试次数
  int get attempts => _attempts;
  
  /// 释放资源
  void dispose() {
    cancel();
  }
}

/// 带超时的操作执行器
class TimeoutOperation {
  /// 执行带超时的操作
  /// 
  /// [operation] 要执行的操作
  /// [timeout] 超时时间
  /// [onTimeout] 超时回调
  /// [tag] 日志标签
  static Future<T?> execute<T>({
    required Future<T> Function() operation,
    required Duration timeout,
    T? Function()? onTimeout,
    String tag = 'TIMEOUT',
  }) async {
    try {
      return await operation().timeout(
        timeout,
        onTimeout: () {
          final logger = ClientLoggerService();
          logger.log('操作超时', tag: tag);
          if (onTimeout != null) {
            final result = onTimeout();
            // 将 T? 转换为 T（如果为null则抛出异常）
            if (result == null) {
              throw TimeoutException('操作超时', timeout);
            }
            return result;
          }
          // 如果没有提供超时回调，抛出超时异常
          throw TimeoutException('操作超时', timeout);
        },
      );
    } catch (e, stackTrace) {
      final logger = ClientLoggerService();
      logger.logError('操作执行失败', error: e, stackTrace: stackTrace);
      if (e is TimeoutException && onTimeout != null) {
        return onTimeout();
      }
      if (onTimeout != null) {
        return onTimeout();
      }
      return null;
    }
  }
}

