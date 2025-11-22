import 'update_info.dart';

/// 更新检查结果
/// 客户端和服务端共享的更新检查结果数据结构
class UpdateCheckResult {
  final bool hasUpdate;
  final UpdateInfo? updateInfo;
  final String? error;

  UpdateCheckResult({
    required this.hasUpdate,
    this.updateInfo,
    this.error,
  });
}

