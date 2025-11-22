import 'dart:io';
import 'package:crypto/crypto.dart';
import '../types/log_callbacks.dart';

/// 文件验证服务
/// 负责文件hash校验等验证操作
/// 客户端和服务端共享
class FileVerificationService {
  /// 日志回调（可选）
  LogCallback? onLog;
  LogErrorCallback? onLogError;

  FileVerificationService({this.onLog, this.onLogError});

  /// 计算文件的SHA256 hash
  Future<String> calculateFileHash(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e, stackTrace) {
      onLogError?.call('计算文件hash失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 校验文件hash
  /// [filePath] 文件路径
  /// [expectedHash] 期望的hash值
  /// 返回 true 如果hash匹配
  Future<bool> verifyFileHash(String filePath, String expectedHash) async {
    try {
      onLog?.call('开始校验文件hash: $filePath', tag: 'VERIFY');
      final actualHash = await calculateFileHash(filePath);
      final isValid = actualHash.toLowerCase() == expectedHash.toLowerCase();

      if (isValid) {
        onLog?.call('文件hash校验通过', tag: 'VERIFY');
      } else {
        onLogError?.call('文件hash校验失败',
            error: '期望: $expectedHash, 实际: $actualHash');
      }

      return isValid;
    } catch (e, stackTrace) {
      onLogError?.call('校验文件hash失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 检查文件是否存在且大小合理
  /// 返回文件大小，如果文件不存在或大小为0则返回null
  Future<int?> checkFileExists(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        return null;
      }

      return fileSize;
    } catch (e, stackTrace) {
      onLogError?.call('检查文件存在性失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}

