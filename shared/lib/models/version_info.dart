/// 版本信息数据类
/// 表示一个版本号，包含版本号和构建号
/// 客户端和服务端共享
class VersionInfo {
  /// 版本号部分（格式: x.y.z）
  final String versionNumber;
  
  /// 构建号
  final String buildNumber;
  
  /// 完整版本号（格式: x.y.z+build）
  final String fullVersion;

  VersionInfo({
    required this.versionNumber,
    required this.buildNumber,
    required this.fullVersion,
  });

  /// 从版本号字符串创建 VersionInfo
  /// 格式: "x.y.z+build"
  factory VersionInfo.fromString(String versionString) {
    final parts = versionString.split('+');
    if (parts.length != 2) {
      throw FormatException(
        '版本号格式不正确: $versionString，应为 x.y.z+build 格式',
      );
    }

    final versionNumber = parts[0].trim();
    final buildNumber = parts[1].trim();

    if (versionNumber.isEmpty || buildNumber.isEmpty) {
      throw FormatException('版本号或构建号为空');
    }

    return VersionInfo(
      versionNumber: versionNumber,
      buildNumber: buildNumber,
      fullVersion: versionString,
    );
  }

  @override
  String toString() => fullVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VersionInfo &&
          runtimeType == other.runtimeType &&
          fullVersion == other.fullVersion;

  @override
  int get hashCode => fullVersion.hashCode;
}

