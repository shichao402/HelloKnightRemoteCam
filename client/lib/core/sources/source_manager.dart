import 'dart:async';
import 'base/sources_base.dart';

/// 数据源管理器
///
/// 负责管理所有数据源的注册、连接状态等
class SourceManager {
  static final SourceManager _instance = SourceManager._internal();
  factory SourceManager() => _instance;
  SourceManager._internal();

  /// 已注册的数据源
  final Map<String, SourceAdapter> _sources = {};

  /// 状态变化控制器
  final _statusController = StreamController<SourceStatusEvent>.broadcast();

  /// 状态变化流
  Stream<SourceStatusEvent> get statusStream => _statusController.stream;

  /// 获取所有数据源
  List<SourceAdapter> get all => _sources.values.toList();

  /// 获取已连接的数据源
  List<SourceAdapter> get connected =>
      _sources.values.where((s) => s.isConnected).toList();

  /// 获取指定类型的数据源
  List<SourceAdapter> getByType(SourceType type) =>
      _sources.values.where((s) => s.type == type).toList();

  /// 获取具有拍摄能力的数据源
  List<CaptureCapability> get captureCapableSources => _sources.values
      .whereType<CaptureCapability>()
      .toList();

  /// 获取具有预览流能力的数据源
  List<StreamCapability> get streamCapableSources => _sources.values
      .whereType<StreamCapability>()
      .toList();

  /// 获取具有文件源能力的数据源
  List<FileSourceCapability> get fileSourceCapableSources => _sources.values
      .whereType<FileSourceCapability>()
      .toList();

  /// 注册数据源
  void register(SourceAdapter source) {
    if (_sources.containsKey(source.id)) {
      throw StateError('数据源 ${source.id} 已存在');
    }

    _sources[source.id] = source;

    // 监听状态变化
    source.statusStream.listen((status) {
      _statusController.add(SourceStatusEvent(
        sourceId: source.id,
        status: status,
        error: source.lastError,
      ));
    });

    _statusController.add(SourceStatusEvent(
      sourceId: source.id,
      status: source.status,
    ));
  }

  /// 注销数据源
  Future<void> unregister(String sourceId) async {
    final source = _sources.remove(sourceId);
    if (source != null) {
      await source.disconnect();
      source.dispose();
    }
  }

  /// 获取数据源
  SourceAdapter? get(String sourceId) => _sources[sourceId];

  /// 获取数据源（泛型版本）
  T? getAs<T extends SourceAdapter>(String sourceId) {
    final source = _sources[sourceId];
    if (source is T) return source;
    return null;
  }

  /// 连接指定数据源
  Future<void> connect(String sourceId) async {
    final source = _sources[sourceId];
    if (source == null) {
      throw StateError('数据源 $sourceId 不存在');
    }
    await source.connect();
  }

  /// 断开指定数据源
  Future<void> disconnect(String sourceId) async {
    final source = _sources[sourceId];
    if (source == null) return;
    await source.disconnect();
  }

  /// 断开所有数据源
  Future<void> disconnectAll() async {
    for (final source in _sources.values) {
      await source.disconnect();
    }
  }

  /// 监听指定数据源的状态
  Stream<SourceStatus> watchSource(String sourceId) {
    return statusStream
        .where((event) => event.sourceId == sourceId)
        .map((event) => event.status);
  }

  /// 释放资源
  void dispose() {
    for (final source in _sources.values) {
      source.dispose();
    }
    _sources.clear();
    _statusController.close();
  }
}

/// 数据源状态事件
class SourceStatusEvent {
  final String sourceId;
  final SourceStatus status;
  final SourceError? error;

  const SourceStatusEvent({
    required this.sourceId,
    required this.status,
    this.error,
  });
}
