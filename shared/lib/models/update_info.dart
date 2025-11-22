/// 更新信息模型
/// 客户端和服务端共享的更新信息数据结构
class UpdateInfo {
  final String version;
  final String versionNumber;
  final String downloadUrl;
  final String fileName;
  final String fileType;
  final String platform;
  final String? releaseNotes;
  final String? fileHash; // SHA256 hash值

  UpdateInfo({
    required this.version,
    required this.versionNumber,
    required this.downloadUrl,
    required this.fileName,
    required this.fileType,
    required this.platform,
    this.releaseNotes,
    this.fileHash,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String,
      versionNumber: json['versionNumber'] as String,
      downloadUrl: json['downloadUrl'] as String,
      fileName: json['fileName'] as String,
      fileType: json['fileType'] as String,
      platform: json['platform'] as String,
      releaseNotes: json['releaseNotes'] as String?,
      fileHash: json['fileHash'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'versionNumber': versionNumber,
      'downloadUrl': downloadUrl,
      'fileName': fileName,
      'fileType': fileType,
      'platform': platform,
      'releaseNotes': releaseNotes,
      'fileHash': fileHash,
    };
  }
}

