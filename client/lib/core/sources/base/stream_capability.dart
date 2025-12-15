import 'dart:async';
import 'dart:typed_data';

/// 预览流能力接口
///
/// 实现此接口的数据源具有实时预览能力
abstract class StreamCapability {
  /// 获取预览流 URL（用于 MJPEG 等流式预览）
  Future<String?> getPreviewStreamUrl();

  /// 开始预览
  Future<void> startPreview();

  /// 停止预览
  Future<void> stopPreview();

  /// 是否正在预览
  bool get isPreviewing;

  /// 预览帧流（用于逐帧预览）
  Stream<Uint8List>? get previewFrameStream;
}
