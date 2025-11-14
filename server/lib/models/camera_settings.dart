import 'package:camera/camera.dart';

// 相机设置
class CameraSettings {
  final String videoQuality;  // 录像质量: ultra, high, medium, low
  final String photoQuality;  // 拍照质量: ultra, high, medium, low
  final bool enableAudio;     // 是否启用音频
  final int previewFps;       // 预览帧率
  final int previewQuality;   // 预览JPEG质量 (0-100)

  const CameraSettings({
    this.videoQuality = 'ultra',
    this.photoQuality = 'ultra',
    this.enableAudio = true,
    this.previewFps = 10,
    this.previewQuality = 70,
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
      };

  // JSON 反序列化
  factory CameraSettings.fromJson(Map<String, dynamic> json) {
    return CameraSettings(
      videoQuality: json['videoQuality'] as String? ?? 'ultra',
      photoQuality: json['photoQuality'] as String? ?? 'ultra',
      enableAudio: json['enableAudio'] as bool? ?? true,
      previewFps: json['previewFps'] as int? ?? 10,
      previewQuality: json['previewQuality'] as int? ?? 70,
    );
  }

  // 复制并修改部分属性
  CameraSettings copyWith({
    String? videoQuality,
    String? photoQuality,
    bool? enableAudio,
    int? previewFps,
    int? previewQuality,
  }) {
    return CameraSettings(
      videoQuality: videoQuality ?? this.videoQuality,
      photoQuality: photoQuality ?? this.photoQuality,
      enableAudio: enableAudio ?? this.enableAudio,
      previewFps: previewFps ?? this.previewFps,
      previewQuality: previewQuality ?? this.previewQuality,
    );
  }
}

