/// 媒体类型枚举
enum MediaType {
  photo,
  video,
}

extension MediaTypeExtension on MediaType {
  String get displayName {
    switch (this) {
      case MediaType.photo:
        return '照片';
      case MediaType.video:
        return '视频';
    }
  }

  String get dbValue {
    switch (this) {
      case MediaType.photo:
        return 'photo';
      case MediaType.video:
        return 'video';
    }
  }

  static MediaType fromDbValue(String value) {
    switch (value) {
      case 'photo':
        return MediaType.photo;
      case 'video':
        return MediaType.video;
      default:
        return MediaType.photo;
    }
  }

  static MediaType fromExtension(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return MediaType.video;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
      case 'heif':
      default:
        return MediaType.photo;
    }
  }
}
