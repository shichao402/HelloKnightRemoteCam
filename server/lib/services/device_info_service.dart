import 'package:flutter/services.dart';
import 'logger_service.dart';

/// 设备信息服务 - 获取Android设备信息
class DeviceInfoService {
  static const MethodChannel _methodChannel = MethodChannel('com.firoyang.helloknightrcc_server/device_info');
  final LoggerService _logger = LoggerService();
  
  /// 获取设备信息
  Future<Map<String, String>?> getDeviceInfo() async {
    try {
      _logger.log('获取设备信息');
      
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
      
      if (result != null) {
        // 转换Map类型
        final deviceInfo = Map<String, String>.fromEntries(
          result.entries.map((entry) => MapEntry(
            entry.key.toString(),
            entry.value.toString(),
          )),
        );
        _logger.log('获取设备信息成功，型号: ${deviceInfo['model']}', tag: 'DEVICE_INFO');
        return deviceInfo;
      } else {
        _logger.logError('获取设备信息失败', error: Exception('返回null'));
        return null;
      }
    } on PlatformException catch (e, stackTrace) {
      _logger.logError('获取设备信息PlatformException', error: e, stackTrace: stackTrace);
      return null;
    } catch (e, stackTrace) {
      _logger.logError('获取设备信息异常', error: e, stackTrace: stackTrace);
      return null;
    }
  }
  
  /// 获取设备标识（用于配置存储的key）
  Future<String?> getDeviceIdentifier() async {
    final info = await getDeviceInfo();
    if (info != null && info['model'] != null) {
      return info['model']; // 使用设备型号作为标识
    }
    return null;
  }
}

