import 'package:camera/camera.dart';
import 'camera_capabilities.dart';

// 相机设置
class CameraSettings {
  final String videoQuality;  // 录像质量: ultra, high, medium, low
  final String photoQuality;  // 拍照质量: ultra, high, medium, low
  final bool enableAudio;     // 是否启用音频
  final int previewFps;       // 预览帧率
  final int previewQuality;   // 预览JPEG质量 (0-100)
  
  // 扩展参数：具体分辨率选择（可选，如果设置则优先使用）
  final Size? photoSize;      // 照片分辨率（null表示使用质量预设）
  final Size? videoSize;      // 视频分辨率（null表示使用质量预设）
  final Size? previewSize;    // 预览分辨率（null表示使用默认）
  final FpsRange? videoFpsRange;  // 视频帧率范围（null表示使用默认）

  const CameraSettings({
    this.videoQuality = 'ultra',
    this.photoQuality = 'ultra',
    this.enableAudio = true,
    this.previewFps = 10,
    this.previewQuality = 70,
    this.photoSize,
    this.videoSize,
    this.previewSize,
    this.videoFpsRange,
  });

  // 将字符串转换为 ResolutionPreset
  ResolutionPreset get videoResolutionPreset {
    switch (videoQuality) {
      case 'ultra':
        return ResolutionPreset.ultraHigh;
      case 'high':
        return ResolutionPreset.high;
      case 'medium':
        return ResolutionPreset.medium;
      case 'low':
        return ResolutionPreset.low;
      default:
        return ResolutionPreset.ultraHigh;
    }
  }

  ResolutionPreset get photoResolutionPreset {
    switch (photoQuality) {
      case 'ultra':
        return ResolutionPreset.ultraHigh;
      case 'high':
        return ResolutionPreset.high;
      case 'medium':
        return ResolutionPreset.medium;
      case 'low':
        return ResolutionPreset.low;
      default:
        return ResolutionPreset.ultraHigh;
    }
  }

  // JSON 序列化
  Map<String, dynamic> toJson() => {
        'videoQuality': videoQuality,
        'photoQuality': photoQuality,
        'enableAudio': enableAudio,
        'previewFps': previewFps,
        'previewQuality': previewQuality,
        if (photoSize != null) 'photoSize': photoSize!.toJson(),
        if (videoSize != null) 'videoSize': videoSize!.toJson(),
        if (previewSize != null) 'previewSize': previewSize!.toJson(),
        if (videoFpsRange != null) 'videoFpsRange': videoFpsRange!.toJson(),
      };

  // JSON 反序列化
  factory CameraSettings.fromJson(Map<String, dynamic> json) {
    return CameraSettings(
      videoQuality: json['videoQuality'] as String? ?? 'ultra',
      photoQuality: json['photoQuality'] as String? ?? 'ultra',
      enableAudio: json['enableAudio'] as bool? ?? true,
      previewFps: json['previewFps'] as int? ?? 10,
      previewQuality: json['previewQuality'] as int? ?? 70,
      photoSize: json['photoSize'] != null 
          ? Size.fromJson(json['photoSize'] as Map<String, dynamic>)
          : null,
      videoSize: json['videoSize'] != null
          ? Size.fromJson(json['videoSize'] as Map<String, dynamic>)
          : null,
      previewSize: json['previewSize'] != null
          ? Size.fromJson(json['previewSize'] as Map<String, dynamic>)
          : null,
      videoFpsRange: json['videoFpsRange'] != null
          ? FpsRange.fromJson(json['videoFpsRange'] as Map<String, dynamic>)
          : null,
    );
  }

  // 复制并修改部分属性
  CameraSettings copyWith({
    String? videoQuality,
    String? photoQuality,
    bool? enableAudio,
    int? previewFps,
    int? previewQuality,
    Size? photoSize,
    Size? videoSize,
    Size? previewSize,
    FpsRange? videoFpsRange,
  }) {
    return CameraSettings(
      videoQuality: videoQuality ?? this.videoQuality,
      photoQuality: photoQuality ?? this.photoQuality,
      enableAudio: enableAudio ?? this.enableAudio,
      previewFps: previewFps ?? this.previewFps,
      previewQuality: previewQuality ?? this.previewQuality,
      photoSize: photoSize ?? this.photoSize,
      videoSize: videoSize ?? this.videoSize,
      previewSize: previewSize ?? this.previewSize,
      videoFpsRange: videoFpsRange ?? this.videoFpsRange,
    );
  }
  
  // 从客户端扩展设置合并（客户端可能包含更多参数）
  CameraSettings mergeFromClient(Map<String, dynamic> clientSettings) {
    return copyWith(
      videoQuality: clientSettings['videoQuality'] as String?,
      photoQuality: clientSettings['photoQuality'] as String?,
      enableAudio: clientSettings['enableAudio'] as bool?,
      previewFps: clientSettings['previewFps'] as int?,
      previewQuality: clientSettings['previewQuality'] as int?,
      photoSize: clientSettings['photoSize'] != null
          ? Size.fromJson(clientSettings['photoSize'] as Map<String, dynamic>)
          : null,
      videoSize: clientSettings['videoSize'] != null
          ? Size.fromJson(clientSettings['videoSize'] as Map<String, dynamic>)
          : null,
      previewSize: clientSettings['previewSize'] != null
          ? Size.fromJson(clientSettings['previewSize'] as Map<String, dynamic>)
          : null,
      videoFpsRange: clientSettings['videoFpsRange'] != null
          ? FpsRange.fromJson(clientSettings['videoFpsRange'] as Map<String, dynamic>)
          : null,
    );
  }
}

