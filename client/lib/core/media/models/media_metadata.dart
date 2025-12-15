/// 媒体元数据
class MediaMetadata {
  final int? width;
  final int? height;
  final Duration? duration; // 视频时长
  final String? codec;
  final double? frameRate;
  final int? bitrate;

  // EXIF 信息
  final String? cameraMake;
  final String? cameraModel;
  final DateTime? dateTaken;
  final double? latitude;
  final double? longitude;

  const MediaMetadata({
    this.width,
    this.height,
    this.duration,
    this.codec,
    this.frameRate,
    this.bitrate,
    this.cameraMake,
    this.cameraModel,
    this.dateTaken,
    this.latitude,
    this.longitude,
  });

  /// 宽高比
  double? get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }

  /// 分辨率描述
  String? get resolution {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return null;
  }

  /// 格式化时长
  String? get formattedDuration {
    if (duration == null) return null;
    final hours = duration!.inHours;
    final minutes = duration!.inMinutes.remainder(60);
    final seconds = duration!.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'durationMs': duration?.inMilliseconds,
        'codec': codec,
        'frameRate': frameRate,
        'bitrate': bitrate,
        'cameraMake': cameraMake,
        'cameraModel': cameraModel,
        'dateTaken': dateTaken?.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      };

  factory MediaMetadata.fromJson(Map<String, dynamic> json) {
    return MediaMetadata(
      width: json['width'] as int?,
      height: json['height'] as int?,
      duration: json['durationMs'] != null
          ? Duration(milliseconds: json['durationMs'] as int)
          : null,
      codec: json['codec'] as String?,
      frameRate: (json['frameRate'] as num?)?.toDouble(),
      bitrate: json['bitrate'] as int?,
      cameraMake: json['cameraMake'] as String?,
      cameraModel: json['cameraModel'] as String?,
      dateTaken: json['dateTaken'] != null
          ? DateTime.tryParse(json['dateTaken'] as String)
          : null,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  MediaMetadata copyWith({
    int? width,
    int? height,
    Duration? duration,
    String? codec,
    double? frameRate,
    int? bitrate,
    String? cameraMake,
    String? cameraModel,
    DateTime? dateTaken,
    double? latitude,
    double? longitude,
  }) {
    return MediaMetadata(
      width: width ?? this.width,
      height: height ?? this.height,
      duration: duration ?? this.duration,
      codec: codec ?? this.codec,
      frameRate: frameRate ?? this.frameRate,
      bitrate: bitrate ?? this.bitrate,
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
      dateTaken: dateTaken ?? this.dateTaken,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
