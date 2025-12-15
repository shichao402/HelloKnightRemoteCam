import 'dart:async';

/// 相机设置（简化版，用于数据源抽象）
class CaptureSettings {
  final String? resolution;
  final int? quality;
  final bool? flashEnabled;
  final String? cameraId;

  const CaptureSettings({
    this.resolution,
    this.quality,
    this.flashEnabled,
    this.cameraId,
  });

  Map<String, dynamic> toJson() => {
        if (resolution != null) 'resolution': resolution,
        if (quality != null) 'quality': quality,
        if (flashEnabled != null) 'flashEnabled': flashEnabled,
        if (cameraId != null) 'cameraId': cameraId,
      };
}

/// 拍摄结果
class CaptureResult {
  /// 是否成功
  final bool success;

  /// 远程文件路径（如果是远程拍摄）
  final String? remotePath;

  /// 本地文件路径（如果已下载）
  final String? localPath;

  /// 文件名
  final String? fileName;

  /// 文件大小
  final int? fileSize;

  /// 错误信息
  final String? error;

  /// 是否为视频
  final bool isVideo;

  const CaptureResult({
    required this.success,
    this.remotePath,
    this.localPath,
    this.fileName,
    this.fileSize,
    this.error,
    this.isVideo = false,
  });

  factory CaptureResult.success({
    String? remotePath,
    String? localPath,
    String? fileName,
    int? fileSize,
    bool isVideo = false,
  }) {
    return CaptureResult(
      success: true,
      remotePath: remotePath,
      localPath: localPath,
      fileName: fileName,
      fileSize: fileSize,
      isVideo: isVideo,
    );
  }

  factory CaptureResult.failure(String error) {
    return CaptureResult(
      success: false,
      error: error,
    );
  }
}

/// 拍摄能力接口
///
/// 实现此接口的数据源具有拍照/录像能力
abstract class CaptureCapability {
  /// 拍照
  ///
  /// 返回拍摄结果，包含远程路径等信息
  Future<CaptureResult> capture();

  /// 开始录像
  Future<bool> startRecording();

  /// 停止录像
  ///
  /// 返回录像结果
  Future<CaptureResult> stopRecording();

  /// 是否正在录像
  bool get isRecording;

  /// 录像状态流
  Stream<bool> get recordingStream;

  /// 获取当前设置
  CaptureSettings get settings;

  /// 更新设置
  Future<bool> updateSettings(CaptureSettings settings);

  /// 拍摄完成事件流（用于监听新拍摄的文件）
  Stream<CaptureResult> get captureStream;
}
