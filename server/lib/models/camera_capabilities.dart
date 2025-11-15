// 相机能力信息模型
class CameraCapabilities {
  final String cameraId;
  final String lensDirection; // back, front, unknown
  final int sensorOrientation;
  final List<Size> photoSizes;
  final List<Size> previewSizes;
  final List<Size> videoSizes;
  final List<String> supportedVideoQualities; // ultra, high, medium, low
  final List<int> afModes;
  final List<int> aeModes;
  final List<int> awbModes;
  final List<FpsRange> fpsRanges;

  const CameraCapabilities({
    required this.cameraId,
    required this.lensDirection,
    required this.sensorOrientation,
    required this.photoSizes,
    required this.previewSizes,
    required this.videoSizes,
    required this.supportedVideoQualities,
    required this.afModes,
    required this.aeModes,
    required this.awbModes,
    required this.fpsRanges,
  });

  factory CameraCapabilities.fromJson(Map<String, dynamic> json) {
    return CameraCapabilities(
      cameraId: json['cameraId'] as String? ?? '',
      lensDirection: json['lensDirection'] as String? ?? 'unknown',
      sensorOrientation: json['sensorOrientation'] as int? ?? 0,
      photoSizes: (json['photoSizes'] as List<dynamic>?)
              ?.map((e) => Size.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      previewSizes: (json['previewSizes'] as List<dynamic>?)
              ?.map((e) => Size.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      videoSizes: (json['videoSizes'] as List<dynamic>?)
              ?.map((e) => Size.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      supportedVideoQualities:
          (json['supportedVideoQualities'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
      afModes: (json['afModes'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      aeModes: (json['aeModes'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      awbModes: (json['awbModes'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      fpsRanges: (json['fpsRanges'] as List<dynamic>?)
              ?.map((e) => FpsRange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cameraId': cameraId,
        'lensDirection': lensDirection,
        'sensorOrientation': sensorOrientation,
        'photoSizes': photoSizes.map((e) => e.toJson()).toList(),
        'previewSizes': previewSizes.map((e) => e.toJson()).toList(),
        'videoSizes': videoSizes.map((e) => e.toJson()).toList(),
        'supportedVideoQualities': supportedVideoQualities,
        'afModes': afModes,
        'aeModes': aeModes,
        'awbModes': awbModes,
        'fpsRanges': fpsRanges.map((e) => e.toJson()).toList(),
      };

  // 获取最大照片尺寸
  Size? get maxPhotoSize {
    if (photoSizes.isEmpty) return null;
    return photoSizes.reduce((a, b) =>
        (a.width * a.height > b.width * b.height) ? a : b);
  }

  // 获取最大视频尺寸
  Size? get maxVideoSize {
    if (videoSizes.isEmpty) return null;
    return videoSizes.reduce((a, b) =>
        (a.width * a.height > b.width * b.height) ? a : b);
  }

  // 获取最大预览尺寸
  Size? get maxPreviewSize {
    if (previewSizes.isEmpty) return null;
    return previewSizes.reduce((a, b) =>
        (a.width * a.height > b.width * b.height) ? a : b);
  }

  // 检查是否支持指定的视频质量
  bool supportsVideoQuality(String quality) {
    return supportedVideoQualities.contains(quality);
  }

  // 获取镜头方向显示名称
  String get lensDirectionDisplayName {
    switch (lensDirection) {
      case 'back':
        return '后置';
      case 'front':
        return '前置';
      default:
        return '未知';
    }
  }
}

// 尺寸信息
class Size {
  final int width;
  final int height;

  const Size({required this.width, required this.height});

  factory Size.fromJson(Map<String, dynamic> json) {
    return Size(
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
      };

  // 获取宽高比
  double get aspectRatio => width / height;

  // 获取显示字符串
  String get displayString => '${width}×${height}';

  // 获取像素数
  int get pixelCount => width * height;

  // 获取百万像素数
  double get megapixels => pixelCount / 1000000.0;

  @override
  String toString() => displayString;
}

// 帧率范围
class FpsRange {
  final int min;
  final int max;

  const FpsRange({required this.min, required this.max});

  factory FpsRange.fromJson(Map<String, dynamic> json) {
    return FpsRange(
      min: json['min'] as int? ?? 0,
      max: json['max'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
      };

  String get displayString => '$min-$max fps';

  @override
  String toString() => displayString;
}

