import 'api_service.dart';
import 'logger_service.dart';

/// 全局ApiService管理器
/// 用于在应用级别访问当前的ApiService实例，以便在应用退出时优雅关闭连接
class ApiServiceManager {
  static final ApiServiceManager _instance = ApiServiceManager._internal();
  factory ApiServiceManager() => _instance;
  ApiServiceManager._internal();

  final ClientLoggerService _logger = ClientLoggerService();
  ApiService? _currentApiService;

  /// 设置当前的ApiService实例
  void setCurrentApiService(ApiService? apiService) {
    _currentApiService = apiService;
    if (apiService != null) {
      _logger.log('设置当前ApiService实例', tag: 'LIFECYCLE');
    } else {
      _logger.log('清除当前ApiService实例', tag: 'LIFECYCLE');
    }
  }

  /// 获取当前的ApiService实例
  ApiService? getCurrentApiService() {
    return _currentApiService;
  }

  /// 优雅关闭当前连接
  /// 尝试发送断开连接通知并关闭WebSocket
  Future<void> gracefulDisconnect() async {
    if (_currentApiService == null) {
      _logger.log('没有活动的ApiService实例，跳过断开连接', tag: 'LIFECYCLE');
      return;
    }

    try {
      _logger.log('开始优雅关闭连接', tag: 'LIFECYCLE');
      
      // 使用ApiService的优雅关闭方法
      await _currentApiService!.gracefulDisconnect();
      
      _logger.log('连接已优雅关闭', tag: 'LIFECYCLE');
    } catch (e, stackTrace) {
      _logger.logError('优雅关闭连接失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 清理资源
  void dispose() {
    if (_currentApiService != null) {
      try {
        _currentApiService!.dispose();
        _logger.log('ApiService资源已释放', tag: 'LIFECYCLE');
      } catch (e, stackTrace) {
        _logger.logError('释放ApiService资源失败', error: e, stackTrace: stackTrace);
      }
      _currentApiService = null;
    }
  }
}

