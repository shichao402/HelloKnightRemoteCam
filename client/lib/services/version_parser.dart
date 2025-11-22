import 'package:shared/shared.dart';
import 'logger_service.dart';

/// 版本文件解析器（客户端包装）
/// 使用 shared 包的 VersionParserService
class VersionParser {
  final ClientLoggerService _logger = ClientLoggerService();
  late final VersionParserService _parserService;

  VersionParser() {
    _parserService = VersionParserService(
      onLog: (message, {tag}) {
        _logger.log(message, tag: tag ?? 'VERSION_PARSER');
      },
      onLogError: (message, {error, stackTrace}) {
        _logger.logError(message, error: error, stackTrace: stackTrace);
      },
    );
  }

  /// 从 YAML 内容解析版本信息（客户端版本）
  /// 抛出异常如果解析失败
  VersionInfo parseVersionFromYaml(String yamlContent) {
    return _parserService.parseClientVersionFromYaml(yamlContent);
  }
}

