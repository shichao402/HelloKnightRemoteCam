import 'dart:async';
import 'source_types.dart';

/// 数据源适配器基础接口
///
/// 所有数据源（手机相机、IP 摄像头、任务服务器等）都需要实现此接口
abstract class SourceAdapter {
  /// 数据源唯一标识
  String get id;

  /// 数据源名称（用于显示）
  String get name;

  /// 数据源类型
  SourceType get type;

  /// 当前状态
  SourceStatus get status;

  /// 状态变化流
  Stream<SourceStatus> get statusStream;

  /// 最后一次错误
  SourceError? get lastError;

  /// 连接到数据源
  Future<void> connect();

  /// 断开连接
  Future<void> disconnect();

  /// 释放资源
  void dispose();

  /// 是否已连接
  bool get isConnected => status == SourceStatus.connected;
}
