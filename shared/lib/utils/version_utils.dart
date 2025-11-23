/// 版本号工具类
/// 提供版本号比较和解析的通用方法
/// 客户端和服务端共享
class VersionUtils {
  /// 比较版本号
  /// 返回 true 如果 version1 > version2
  static bool compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((e) => int.parse(e)).toList();
    final v2Parts = version2.split('.').map((e) => int.parse(e)).toList();

    // 确保两个版本号都有3个部分
    while (v1Parts.length < 3) {
      v1Parts.add(0);
    }
    while (v2Parts.length < 3) {
      v2Parts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (v1Parts[i] > v2Parts[i]) return true;
      if (v1Parts[i] < v2Parts[i]) return false;
    }

    return false; // 相等
  }

  /// 比较版本号（大于等于）
  /// 返回 true 如果 version1 >= version2
  static bool compareVersionsGreaterOrEqual(String version1, String version2) {
    final v1Parts = version1.split('.').map((e) => int.parse(e)).toList();
    final v2Parts = version2.split('.').map((e) => int.parse(e)).toList();

    // 确保两个版本号都有3个部分
    while (v1Parts.length < 3) {
      v1Parts.add(0);
    }
    while (v2Parts.length < 3) {
      v2Parts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (v1Parts[i] > v2Parts[i]) return true;
      if (v1Parts[i] < v2Parts[i]) return false;
    }

    return true; // 相等
  }

  /// 比较完整版本号（包含构建号，格式: x.y.z+build）
  /// 返回 true 如果 version1 >= version2
  static bool compareFullVersions(String version1, String version2) {
    // 分离版本号和构建号
    final v1Parts = version1.split('+');
    final v2Parts = version2.split('+');

    final v1Version = v1Parts[0];
    final v2Version = v2Parts[0];
    final v1Build = v1Parts.length > 1 ? int.tryParse(v1Parts[1]) ?? 0 : 0;
    final v2Build = v2Parts.length > 1 ? int.tryParse(v2Parts[1]) ?? 0 : 0;

    // 先比较版本号
    final versionCompare = compareVersions(v1Version, v2Version);
    if (versionCompare) return true;
    if (!compareVersions(v2Version, v1Version)) {
      // 版本号相等，比较构建号
      return v1Build >= v2Build;
    }
    return false;
  }

  /// 从文件名提取版本号（格式: x.y.z+build 或 x.y.zbuild）
  /// 例如: 
  ///   HelloKnightRCC_macos_1.0.7+5.zip -> 1.0.7+5
  ///   HelloKnightRCC_macos_1.0.7build10.zip -> 1.0.7+10
  static String? extractVersionFromFileName(String fileName) {
    try {
      // 先尝试匹配 build 格式: _x.y.zbuildN
      final buildRegex = RegExp(r'_(\d+\.\d+\.\d+)build(\d+)');
      final buildMatch = buildRegex.firstMatch(fileName);
      if (buildMatch != null) {
        final version = buildMatch.group(1);
        final build = buildMatch.group(2);
        return '$version+$build';
      }
      
      // 再尝试匹配 + 格式: _x.y.z+N 或 _x.y.z
      final plusRegex = RegExp(r'_(\d+\.\d+\.\d+(?:\+\d+)?)');
      final plusMatch = plusRegex.firstMatch(fileName);
      if (plusMatch != null) {
        return plusMatch.group(1);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
}

