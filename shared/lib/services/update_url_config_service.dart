import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// 更新 URL 配置服务
/// 从 VERSION.yaml 文件中读取更新检查 URL 配置
/// 从 assets/VERSION.yaml 读取配置
class UpdateUrlConfigService {
  /// 从 assets/VERSION.yaml 读取更新检查 URL 列表
  /// 返回 [giteeUrl, githubUrl]，优先使用 Gitee
  static Future<List<String>> getUpdateCheckUrls() async {
    List<String> urls = [];
    
    try {
      // 从 assets/VERSION.yaml 读取
      final content = await rootBundle.loadString('assets/VERSION.yaml');
      final yamlDoc = loadYaml(content);
      if (yamlDoc is Map) {
        final update = yamlDoc['update'];
        if (update is Map) {
          final gitee = update['gitee'];
          final github = update['github'];
          
          if (gitee is Map) {
            final giteeUrl = gitee['url'];
            if (giteeUrl != null && giteeUrl.toString().isNotEmpty) {
              urls.add(giteeUrl.toString());
            }
          }
          
          if (github is Map) {
            final githubUrl = github['url'];
            if (githubUrl != null && githubUrl.toString().isNotEmpty) {
              urls.add(githubUrl.toString());
            }
          }
        }
      }
    } catch (e) {
      // 读取失败，返回空列表
    }
    
    return urls;
  }
}

