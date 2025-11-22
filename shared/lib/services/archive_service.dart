import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import '../types/log_callbacks.dart';

/// 归档文件服务
/// 负责zip文件的解压等操作
/// 客户端和服务端共享
class ArchiveService {
  /// 日志回调（可选）
  LogCallback? onLog;
  LogErrorCallback? onLogError;

  ArchiveService({this.onLog, this.onLogError});

  /// 解压zip文件
  /// [zipPath] zip文件路径
  /// [extractDir] 解压目标目录
  /// 返回解压后找到的安装文件路径（根据平台优先返回apk/dmg/exe），如果找不到则返回null
  Future<String?> extractZipFile(String zipPath, String extractDir) async {
    try {
      onLog?.call('开始解压zip文件: $zipPath', tag: 'ARCHIVE');

      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 创建解压目录
      final extractDirectory = Directory(extractDir);
      if (!await extractDirectory.exists()) {
        await extractDirectory.create(recursive: true);
      }

      // 解压所有文件并查找平台特定的安装文件
      String? apkFilePath; // 优先查找APK文件（Android）
      String? dmgFilePath; // 查找DMG文件（macOS）
      String? exeFilePath; // 查找EXE文件（Windows）

      for (final file in archive) {
        final filePath = path.join(extractDir, file.name);

        if (file.isFile) {
          final outputFile = File(filePath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);

          // 根据文件扩展名分类查找
          final ext = path.extension(filePath).toLowerCase();
          if (ext == '.apk') {
            apkFilePath = filePath;
            onLog?.call('找到APK文件: $filePath', tag: 'ARCHIVE');
          } else if (ext == '.dmg') {
            dmgFilePath = filePath;
            onLog?.call('找到DMG文件: $filePath', tag: 'ARCHIVE');
          } else if (ext == '.exe' || ext == '.msi') {
            exeFilePath = filePath;
            onLog?.call('找到EXE/MSI文件: $filePath', tag: 'ARCHIVE');
          }
        } else {
          // 创建目录
          final dir = Directory(filePath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        }
      }

      // 根据平台优先返回对应的文件，如果都找不到则返回null
      String? result;
      if (Platform.isAndroid) {
        result = apkFilePath;
      } else if (Platform.isMacOS) {
        // macOS: GitHub Actions打包的zip中包含dmg文件，优先查找dmg
        result = dmgFilePath;
      } else if (Platform.isWindows) {
        result = exeFilePath;
      } else {
        result = apkFilePath ?? dmgFilePath ?? exeFilePath;
      }

      if (result == null) {
        onLog?.call('zip文件解压完成，但未找到预期的安装文件，将打开zip文件本身', tag: 'ARCHIVE');
      } else {
        onLog?.call('zip文件解压完成: $extractDir, 返回文件: $result', tag: 'ARCHIVE');
      }
      return result;
    } catch (e, stackTrace) {
      onLogError?.call('解压zip文件失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}

