// 相机状态枚举
enum CameraStatus {
  idle,          // 空闲
  takingPhoto,   // 拍照中
  recording,     // 录像中
  reconfiguring, // 重新配置中
}

extension CameraStatusExtension on CameraStatus {
  String get displayName {
    switch (this) {
      case CameraStatus.idle:
        return '空闲';
      case CameraStatus.takingPhoto:
        return '拍照中';
      case CameraStatus.recording:
        return '录像中';
      case CameraStatus.reconfiguring:
        return '配置中';
    }
  }

  bool get isLocked {
    // 录像中时锁定设置
    return this == CameraStatus.recording;
  }

  bool get canChangeSettings {
    // 只有空闲和拍照时可以更改设置
    return this == CameraStatus.idle || this == CameraStatus.takingPhoto;
  }
}

