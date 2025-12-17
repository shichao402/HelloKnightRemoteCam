import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../models/camera_settings.dart';
import '../models/file_info.dart';
import '../models/connection_error.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'websocket_connection.dart';

/// API服务
/// 
/// 职责：
/// - 提供业务API（拍照、录像、文件管理等）
/// - 封装HTTP请求（文件下载、缩略图等）
/// 
/// 不负责：
/// - 连接管理（由 WebSocketConnection 处理）
/// - 连接状态维护（由 WebSocketConnection 处理）
class ApiService {
  final String baseUrl;
  final String host;
  final int port;
  final ClientLoggerService logger = ClientLoggerService();
  final VersionService _versionService = VersionService();
  late final HttpClient _httpClient;

  // WebSocket连接管理器
  late final WebSocketConnection _connection;
  
  /// 获取连接管理器（供外部访问连接状态）
  WebSocketConnection get connection => _connection;

  /// 获取连接状态
  ConnectionState get connectionState => _connection.state;

  /// 连接状态流
  Stream<ConnectionStateChange> get connectionStateStream =>
      _connection.stateStream;

  /// 通知流（用于监听服务器推送的通知）
  Stream<Map<String, dynamic>> get webSocketNotifications =>
      _connection.notificationStream;

  /// 是否已连接
  bool get isWebSocketConnected => _connection.isConnected;

  /// 是否已注册
  bool get isRegistered => _connection.isRegistered;

  /// 最后一次连接错误
  ConnectionError? get lastConnectionError => _connection.lastError;

  /// 服务器版本
  String? get serverVersion => _connection.serverVersion;

  /// 预览尺寸
  Map<String, dynamic>? get previewSize => _connection.previewSize;

  ApiService({
    required String host,
    required int port,
  })  : baseUrl = 'http://$host:$port',
        host = host,
        port = port {
    // 创建WebSocket连接管理器
    _connection = WebSocketConnection(host: host, port: port);
    
    // 创建自定义的HttpClient，强制使用IPv4
    _httpClient = HttpClient();
    _httpClient.autoUncompress = true;
    _httpClient.connectionTimeout = const Duration(seconds: 3);
    _httpClient.idleTimeout = const Duration(seconds: 5);
  }

  // ==================== 连接管理 ====================

  /// 连接到服务器
  Future<ConnectionError?> connect() async {
    return await _connection.connect();
  }

  /// 连接WebSocket（兼容旧API）
  Future<void> connectWebSocket() async {
    final error = await _connection.connect();
    if (error != null) {
      throw Exception(error.message);
    }
  }

  /// 断开WebSocket连接
  void disconnectWebSocket() {
    _connection.disconnect();
  }

  /// 优雅关闭连接
  Future<void> gracefulDisconnect() async {
    logger.log('开始优雅关闭WebSocket连接', tag: 'LIFECYCLE');
    await _connection.disconnect();
    logger.log('WebSocket连接已优雅关闭', tag: 'LIFECYCLE');
  }

  /// 释放资源
  void dispose() {
    _connection.dispose();
    _httpClient.close(force: true);
  }

  // ==================== 业务API ====================

  /// 测试连接（ping）
  Future<ConnectionError?> ping() async {
    try {
      logger.logCommand('ping', details: '测试服务器连接（WebSocket）');

      // 如果未连接，先连接
      if (!_connection.isConnected) {
        final connectError = await _connection.connect();
        if (connectError != null) {
          logger.logCommandResponse('ping',
              success: false, error: connectError.message);
          return connectError;
        }
      }

      // 发送ping请求
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'ping'});
      final result = await _connection.sendRequest('ping', {});
      final success = result['success'] == true;
      logger.logCommandResponse('ping', success: success, result: result);

      if (success) {
        return null;
      } else {
        return ConnectionError(
          code: ConnectionErrorCode.connectionRefused,
          message: result['error'] as String? ?? '连接失败',
        );
      }
    } catch (e, stackTrace) {
      logger.logError('Ping失败', error: e, stackTrace: stackTrace);
      final error = ConnectionError.fromException(e);
      logger.logCommandResponse('ping', success: false, error: error.message);
      return error;
    }
  }

  /// 注册设备
  Future<Map<String, dynamic>> registerDevice(String deviceModel) async {
    try {
      final clientVersion = await _versionService.getVersion();

      logger.logCommand('registerDevice',
          params: {'deviceModel': deviceModel, 'clientVersion': clientVersion},
          details: '注册设备');
      logger.logApiCall('WEBSOCKET', '/ws', params: {
        'action': 'registerDevice',
        'deviceModel': deviceModel,
        'clientVersion': clientVersion
      });

      final error = await _connection.registerDevice(deviceModel);
      if (error != null) {
        logger.logCommandResponse('registerDevice',
            success: false, error: error.message);
        return {'success': false, 'error': error.message};
      }

      logger.logCommandResponse('registerDevice', success: true);
      return {'success': true, 'exclusive': true};
    } catch (e, stackTrace) {
      logger.logError('注册设备失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('registerDevice',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 拍照
  Future<Map<String, dynamic>> capture() async {
    try {
      logger.logCommand('capture', details: '拍照指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'capture'});
      final result = await _connection.sendRequest('capture', {});
      logger.logCommandResponse('capture',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('拍照请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('capture', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 开始录像
  Future<Map<String, dynamic>> startRecording() async {
    try {
      logger.logCommand('startRecording', details: '开始录像指令');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'startRecording'});
      final result = await _connection.sendRequest('startRecording', {});
      logger.logCommandResponse('startRecording',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('开始录像请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('startRecording',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 停止录像
  Future<Map<String, dynamic>> stopRecording() async {
    try {
      logger.logCommand('stopRecording', details: '停止录像指令');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'stopRecording'});
      final result = await _connection.sendRequest('stopRecording', {});
      logger.logCommandResponse('stopRecording',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('停止录像请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('stopRecording',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 获取文件列表（支持分页和增量获取）
  Future<Map<String, dynamic>> getFileList({
    int? page,
    int? pageSize,
    int? since,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (page != null) params['page'] = page;
      if (pageSize != null) params['pageSize'] = pageSize;
      if (since != null) params['since'] = since;

      logger.logCommand('getFileList',
          details: '获取文件列表指令${params.isNotEmpty ? ' ($params)' : ''}');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'getFiles', ...params});
      final result = await _connection.sendRequest('getFiles', params);

      if (result['success'] == true) {
        // 将JSON转换为FileInfo对象
        result['pictures'] = (result['pictures'] as List?)
                ?.map((json) => FileInfo.fromJson(json))
                .toList() ??
            [];
        result['videos'] = (result['videos'] as List?)
                ?.map((json) => FileInfo.fromJson(json))
                .toList() ??
            [];
      }

      logger.logCommandResponse('getFileList',
          success: result['success'] == true,
          result: {
            'pictures_count': (result['pictures'] as List?)?.length ?? 0,
            'videos_count': (result['videos'] as List?)?.length ?? 0,
            'total': result['total'],
            'page': result['page'],
            'hasMore': result['hasMore'],
          },
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取文件列表失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getFileList',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 删除文件
  Future<Map<String, dynamic>> deleteFile(String remotePath) async {
    try {
      logger.logCommand('deleteFile',
          params: {'path': remotePath}, details: '删除文件指令');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'deleteFile', 'path': remotePath});
      final result =
          await _connection.sendRequest('deleteFile', {'path': remotePath});
      logger.logCommandResponse('deleteFile',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('删除文件失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('deleteFile',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 切换文件星标状态
  Future<Map<String, dynamic>> toggleStarred(String remotePath) async {
    try {
      logger.logCommand('toggleStarred',
          params: {'path': remotePath}, details: '切换文件星标状态');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'toggleStarred', 'path': remotePath});
      final result =
          await _connection.sendRequest('toggleStarred', {'path': remotePath});
      logger.logCommandResponse('toggleStarred',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('切换文件星标状态失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('toggleStarred',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 获取设置状态
  Future<Map<String, dynamic>> getSettingsStatus() async {
    try {
      logger.logCommand('getSettingsStatus', details: '获取设置状态指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getStatus'});
      final result = await _connection.sendRequest('getStatus', {});
      logger.logCommandResponse('getSettingsStatus',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设置状态失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getSettingsStatus',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 更新设置
  Future<Map<String, dynamic>> updateSettings(CameraSettings settings) async {
    try {
      logger.logCommand('updateSettings',
          params: settings.toJson(), details: '更新相机设置');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'updateSettings', ...settings.toJson()});
      final result =
          await _connection.sendRequest('updateSettings', settings.toJson());
      logger.logCommandResponse('updateSettings',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('更新设置失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('updateSettings',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 设置方向锁定状态
  Future<Map<String, dynamic>> setOrientationLock(bool locked) async {
    try {
      logger.logCommand('setOrientationLock',
          params: {'locked': locked}, details: '设置方向锁定: $locked');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'setOrientationLock', 'locked': locked});
      final result = await _connection
          .sendRequest('setOrientationLock', {'locked': locked});
      logger.logCommandResponse('setOrientationLock',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('设置方向锁定失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('setOrientationLock',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 设置锁定状态下的旋转角度
  Future<Map<String, dynamic>> setLockedRotationAngle(int angle) async {
    try {
      logger.logCommand('setLockedRotationAngle',
          params: {'angle': angle}, details: '设置锁定旋转角度: $angle');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'setLockedRotationAngle', 'angle': angle});
      final result = await _connection
          .sendRequest('setLockedRotationAngle', {'angle': angle});
      logger.logCommandResponse('setLockedRotationAngle',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('设置锁定旋转角度失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('setLockedRotationAngle',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 获取当前设置
  Future<Map<String, dynamic>> getSettings() async {
    try {
      logger.logCommand('getSettings', details: '获取相机设置指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getSettings'});
      final result = await _connection.sendRequest('getSettings', {});

      if (result['success'] == true && result['settings'] != null) {
        final settingsMap = result['settings'];
        if (settingsMap is Map) {
          result['settings'] =
              CameraSettings.fromJson(_convertMap(settingsMap));
        } else {
          logger.logError('设置数据格式错误',
              error:
                  Exception('settings不是Map类型: ${settingsMap.runtimeType}'));
        }
      }

      logger.logCommandResponse('getSettings',
          success: result['success'] == true,
          result: result['settings'],
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设置失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getSettings',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 获取指定相机的能力信息
  Future<Map<String, dynamic>> getCameraCapabilities(String cameraId) async {
    try {
      logger.logCommand('getCameraCapabilities',
          params: {'cameraId': cameraId}, details: '获取相机能力信息');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'getCameraCapabilities', 'cameraId': cameraId});
      final result = await _connection
          .sendRequest('getCameraCapabilities', {'cameraId': cameraId});
      logger.logCommandResponse('getCameraCapabilities',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取相机能力信息失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getCameraCapabilities',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 获取所有相机的能力信息
  Future<Map<String, dynamic>> getAllCameraCapabilities() async {
    try {
      logger.logCommand('getAllCameraCapabilities', details: '获取所有相机能力信息');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'getAllCameraCapabilities'});
      final result =
          await _connection.sendRequest('getAllCameraCapabilities', {});
      logger.logCommandResponse('getAllCameraCapabilities',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取所有相机能力信息失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getAllCameraCapabilities',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 获取设备信息
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      logger.logCommand('getDeviceInfo', details: '获取设备信息');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'getDeviceInfo'});
      final result = await _connection.sendRequest('getDeviceInfo', {});
      logger.logCommandResponse('getDeviceInfo',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设备信息失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getDeviceInfo',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==================== HTTP API ====================

  /// 获取预览流URL
  Future<String> getPreviewStreamUrl() async {
    try {
      final clientVersion = await _versionService.getVersion();
      return '$baseUrl/preview/stream?clientVersion=${Uri.encodeComponent(clientVersion)}';
    } catch (e) {
      logger.logError('获取预览流URL失败', error: e);
      return '$baseUrl/preview/stream';
    }
  }

  /// 获取文件下载URL
  String getFileDownloadUrl(String remotePath) {
    return '$baseUrl/file/download?path=${Uri.encodeComponent(remotePath)}';
  }

  /// 获取缩略图URL
  Future<String> getThumbnailUrl(String remotePath, bool isVideo) async {
    try {
      final clientVersion = await _versionService.getVersion();
      return '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remotePath)}&type=${isVideo ? 'video' : 'image'}&clientVersion=${Uri.encodeComponent(clientVersion)}';
    } catch (e) {
      logger.logError('获取缩略图URL失败', error: e);
      return '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remotePath)}&type=${isVideo ? 'video' : 'image'}';
    }
  }

  /// 下载缩略图
  Future<Uint8List?> downloadThumbnail(String remotePath, bool isVideo) async {
    try {
      final thumbnailUrl = await getThumbnailUrl(remotePath, isVideo);
      final uri = Uri.parse(thumbnailUrl);
      final request = await _httpClient.getUrl(uri);
      await _addVersionHeader(request);
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return Uint8List.fromList(bytes);
      }
      return null;
    } catch (e) {
      logger.logError('下载缩略图失败', error: e);
      return null;
    }
  }

  // ==================== 私有方法 ====================

  /// 为HTTP请求添加版本头
  Future<void> _addVersionHeader(HttpClientRequest request) async {
    try {
      final clientVersion = await _versionService.getVersion();
      request.headers.add('X-Client-Version', clientVersion);
    } catch (e) {
      logger.logError('添加版本头失败', error: e);
    }
  }

  /// 转换Map类型
  Map<String, dynamic> _convertMap(Map map) {
    return Map<String, dynamic>.fromEntries(
      map.entries.map((entry) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          return MapEntry(key, _convertMap(value));
        } else if (value is List) {
          return MapEntry(
              key,
              value.map((item) {
                if (item is Map) {
                  return _convertMap(item);
                }
                return item;
              }).toList());
        } else {
          return MapEntry(key, value);
        }
      }),
    );
  }
}
