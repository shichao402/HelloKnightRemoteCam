import 'dart:async';
import 'dart:typed_data';
import 'capture_capability.dart';

/// 预览帧数据
class PreviewFrame {
  /// 帧数据（JPEG/PNG 格式）
  final Uint8List data;

  /// 帧宽度
  final int? width;

  /// 帧高度
  final int? height;

  /// 时间戳
  final DateTime timestamp;

  const PreviewFrame({
    required this.data,
    this.width,
    this.height,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _Now();

  @override
  String toString() => 'PreviewFrame(${data.length} bytes, ${width}x$height)';
}

// 用于默认时间戳的辅助类
class _Now implements DateTime {
  const _Now();

  DateTime get _now => DateTime.now();

  @override
  int get year => _now.year;
  @override
  int get month => _now.month;
  @override
  int get day => _now.day;
  @override
  int get hour => _now.hour;
  @override
  int get minute => _now.minute;
  @override
  int get second => _now.second;
  @override
  int get millisecond => _now.millisecond;
  @override
  int get microsecond => _now.microsecond;
  @override
  int get weekday => _now.weekday;
  @override
  bool get isUtc => _now.isUtc;
  @override
  int get millisecondsSinceEpoch => _now.millisecondsSinceEpoch;
  @override
  int get microsecondsSinceEpoch => _now.microsecondsSinceEpoch;
  @override
  String get timeZoneName => _now.timeZoneName;
  @override
  Duration get timeZoneOffset => _now.timeZoneOffset;

  @override
  DateTime add(Duration duration) => _now.add(duration);
  @override
  DateTime subtract(Duration duration) => _now.subtract(duration);
  @override
  Duration difference(DateTime other) => _now.difference(other);
  @override
  bool isAfter(DateTime other) => _now.isAfter(other);
  @override
  bool isBefore(DateTime other) => _now.isBefore(other);
  @override
  bool isAtSameMomentAs(DateTime other) => _now.isAtSameMomentAs(other);
  @override
  int compareTo(DateTime other) => _now.compareTo(other);
  @override
  DateTime toLocal() => _now.toLocal();
  @override
  DateTime toUtc() => _now.toUtc();
  @override
  String toIso8601String() => _now.toIso8601String();
  @override
  String toString() => _now.toString();
}

/// 拍摄控制器能力声明
class CaptureControllerCapability {
  /// 是否支持拍照
  final bool canCapture;

  /// 是否支持录像
  final bool canRecord;

  /// 是否支持实时预览
  final bool canPreview;

  /// 是否支持预览流 URL（如 MJPEG）
  final bool hasPreviewUrl;

  /// 是否支持预览帧流
  final bool hasPreviewFrameStream;

  /// 是否远程设备
  final bool isRemote;

  /// 是否需要连接
  final bool requiresConnection;

  /// 是否支持闪光灯
  final bool hasFlash;

  /// 是否支持切换摄像头
  final bool canSwitchCamera;

  /// 是否支持缩放
  final bool canZoom;

  const CaptureControllerCapability({
    this.canCapture = true,
    this.canRecord = false,
    this.canPreview = false,
    this.hasPreviewUrl = false,
    this.hasPreviewFrameStream = false,
    this.isRemote = false,
    this.requiresConnection = false,
    this.hasFlash = false,
    this.canSwitchCamera = false,
    this.canZoom = false,
  });

  /// 手机相机能力（远程）
  static const phoneCamera = CaptureControllerCapability(
    canCapture: true,
    canRecord: true,
    canPreview: true,
    hasPreviewUrl: true,
    hasPreviewFrameStream: false,
    isRemote: true,
    requiresConnection: true,
    hasFlash: true,
    canSwitchCamera: true,
    canZoom: true,
  );

  /// 本地摄像头能力
  static const localCamera = CaptureControllerCapability(
    canCapture: true,
    canRecord: true,
    canPreview: true,
    hasPreviewUrl: false,
    hasPreviewFrameStream: true,
    isRemote: false,
    requiresConnection: false,
    hasFlash: false,
    canSwitchCamera: true,
    canZoom: false,
  );
}

/// 统一拍摄控制器接口
///
/// 抽象拍摄能力，支持不同来源（手机相机、本地摄像头等）
abstract class CaptureController {
  /// 控制器能力声明
  CaptureControllerCapability get capability;

  /// 是否已初始化
  bool get isInitialized;

  /// 初始化控制器
  Future<void> initialize();

  // ==================== 预览相关 ====================

  /// 获取预览流 URL（用于 MJPEG 等流式预览）
  /// 仅当 capability.hasPreviewUrl 为 true 时可用
  Future<String?> getPreviewStreamUrl();

  /// 预览帧流（用于逐帧预览）
  /// 仅当 capability.hasPreviewFrameStream 为 true 时可用
  Stream<PreviewFrame>? get previewFrameStream;

  /// 开始预览
  Future<void> startPreview();

  /// 停止预览
  Future<void> stopPreview();

  /// 是否正在预览
  bool get isPreviewing;

  // ==================== 拍摄相关 ====================

  /// 拍照
  Future<CaptureResult> capture();

  /// 开始录像
  Future<bool> startRecording();

  /// 停止录像
  Future<CaptureResult> stopRecording();

  /// 是否正在录像
  bool get isRecording;

  /// 录像状态流
  Stream<bool> get recordingStream;

  /// 拍摄完成事件流
  Stream<CaptureResult> get captureStream;

  // ==================== 设置相关 ====================

  /// 获取当前设置
  CaptureSettings get settings;

  /// 更新设置
  Future<bool> updateSettings(CaptureSettings settings);

  /// 切换摄像头（前置/后置）
  /// 仅当 capability.canSwitchCamera 为 true 时可用
  Future<bool> switchCamera();

  /// 设置闪光灯模式
  /// 仅当 capability.hasFlash 为 true 时可用
  Future<bool> setFlashMode(FlashMode mode);

  /// 设置缩放级别
  /// 仅当 capability.canZoom 为 true 时可用
  Future<bool> setZoom(double zoom);

  // ==================== 生命周期 ====================

  /// 释放资源
  Future<void> dispose();
}

/// 闪光灯模式
enum FlashMode {
  off,
  on,
  auto,
  torch,
}

/// 摄像头位置
enum CameraPosition {
  front,
  back,
  external,
}
