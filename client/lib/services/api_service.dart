import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/camera_settings.dart';
import '../models/file_info.dart';
import 'logger_service.dart';

class ApiService {
  final String baseUrl;
  final String host;
  final int port;
  final ClientLoggerService logger = ClientLoggerService();
  late final HttpClient _httpClient;
  
  // WebSocket连接管理
  WebSocketChannel? _webSocketChannel;
  StreamSubscription? _webSocketSubscription;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _messageIdCounter = 0;
  bool _useWebSocket = true; // 是否使用WebSocket（默认true）
  
  // WebSocket通知流（用于监听服务器推送的通知）
  // 注意：这个stream会与_handleWebSocketMessage共享同一个stream，所以需要创建一个广播stream
  StreamController<Map<String, dynamic>>? _notificationController;
  
  Stream<Map<String, dynamic>>? get webSocketNotifications {
    if (_webSocketChannel == null) {
      return null;
    }
    // 如果还没有创建通知控制器，创建一个广播stream
    _notificationController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _notificationController!.stream;
  }

  ApiService({
    required String host,
    required int port,
  }) : baseUrl = 'http://$host:$port',
       host = host,
       port = port {
    // 创建自定义的HttpClient，强制使用IPv4
    _httpClient = HttpClient();
    _httpClient.autoUncompress = true;
    _httpClient.connectionTimeout = const Duration(seconds: 3); // 缩短连接超时时间
    _httpClient.idleTimeout = const Duration(seconds: 5); // 设置空闲超时
  }

  // 断开WebSocket连接（不断开HTTP客户端）
  void disconnectWebSocket() {
    _webSocketSubscription?.cancel();
    _webSocketSubscription = null;
    _webSocketChannel?.sink.close();
    _webSocketChannel = null;
    _notificationController?.close();
    _notificationController = null;
    _useWebSocket = false;
    _pendingRequests.clear();
  }

  // 检查WebSocket是否已连接
  bool get isWebSocketConnected => _webSocketChannel != null;

  // 优雅关闭连接（尝试发送断开通知后关闭）
  Future<void> gracefulDisconnect() async {
    if (_webSocketChannel == null) {
      logger.log('WebSocket未连接，跳过断开操作', tag: 'LIFECYCLE');
      return;
    }

    try {
      logger.log('开始优雅关闭WebSocket连接', tag: 'LIFECYCLE');
      
      // WebSocket关闭时会自动触发服务器端的onDone回调，服务器会自动清理连接
      // 不需要发送额外的断开消息，直接关闭即可
      disconnectWebSocket();
      
      logger.log('WebSocket连接已优雅关闭', tag: 'LIFECYCLE');
    } catch (e, stackTrace) {
      logger.logError('优雅关闭连接失败', error: e, stackTrace: stackTrace);
      // 即使失败也尝试强制断开
      disconnectWebSocket();
    }
  }
  
  // 释放资源
  void dispose() {
    disconnectWebSocket();
    _httpClient.close(force: true);
  }
  
  // 连接WebSocket
  Future<void> connectWebSocket() async {
    if (_webSocketChannel != null) {
      return; // 已经连接
    }
    
    try {
      final wsUrl = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
      final uri = Uri.parse('$wsUrl/ws');
      logger.log('连接WebSocket: $uri', tag: 'WEBSOCKET');
      
      _webSocketChannel = WebSocketChannel.connect(uri);
      
      // 创建通知控制器（如果还没有创建）
      _notificationController ??= StreamController<Map<String, dynamic>>.broadcast();
      
      _webSocketSubscription = _webSocketChannel!.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          logger.logError('WebSocket错误', error: error);
          _webSocketChannel = null;
          _notificationController?.close();
          _notificationController = null;
          _useWebSocket = false; // 回退到HTTP
        },
        onDone: () {
          logger.log('WebSocket连接关闭', tag: 'WEBSOCKET');
          _webSocketChannel = null;
          _notificationController?.close();
          _notificationController = null;
          _useWebSocket = false; // 回退到HTTP
        },
        cancelOnError: false,
      );
      
      logger.log('WebSocket连接成功', tag: 'WEBSOCKET');
    } catch (e, stackTrace) {
      logger.logError('WebSocket连接失败', error: e, stackTrace: stackTrace);
      _webSocketChannel = null;
      _useWebSocket = false; // 回退到HTTP
    }
  }
  
  // 处理WebSocket消息
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      final messageType = data['type'] as String?;
      
      if (messageType == 'response') {
        // 处理响应消息
        final messageId = data['id'] as String?;
        if (messageId != null && _pendingRequests.containsKey(messageId)) {
          final completer = _pendingRequests.remove(messageId)!;
          if (data['success'] == true) {
            // 服务器端返回的数据在data字段中，需要转换类型
            final responseData = data['data'];
            if (responseData is Map) {
              completer.complete(_convertMap(responseData));
            } else {
              completer.complete(responseData as Map<String, dynamic>? ?? {});
            }
          } else {
            completer.complete({
              'success': false,
              'error': data['error'] as String? ?? '未知错误',
            });
          }
        }
      } else if (messageType == 'notification') {
        // 处理通知消息（如new_files）
        // 广播通知消息给所有监听者
        logger.log('收到WebSocket通知: $data', tag: 'WEBSOCKET');
        _notificationController?.add(data);
      }
    } catch (e) {
      logger.logError('解析WebSocket消息失败', error: e);
    }
  }
  
  // 转换Map类型（从Map<Object?, Object?>转换为Map<String, dynamic>）
  Map<String, dynamic> _convertMap(Map map) {
    return Map<String, dynamic>.fromEntries(
      map.entries.map((entry) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          return MapEntry(key, _convertMap(value));
        } else if (value is List) {
          return MapEntry(key, value.map((item) {
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
  
  // 通过WebSocket发送请求
  Future<Map<String, dynamic>> _sendWebSocketRequest(String action, Map<String, dynamic> params) async {
    if (_webSocketChannel == null) {
      await connectWebSocket();
    }
    
    if (_webSocketChannel == null) {
      throw Exception('WebSocket未连接');
    }
    
    final messageId = 'msg_${++_messageIdCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[messageId] = completer;
    
    try {
      final request = json.encode({
        'id': messageId,
        'type': 'request',
        'action': action,
        'params': params,
      });
      
      _webSocketChannel!.sink.add(request);
      
      // 设置超时（10秒）
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingRequests.remove(messageId);
          return {'success': false, 'error': '请求超时'};
        },
      );
    } catch (e) {
      _pendingRequests.remove(messageId);
      rethrow;
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  // 发送HTTP请求的通用方法
  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required String path,
    Map<String, String>? headers,
    String? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      logger.log('尝试连接到: $uri', tag: 'CONNECTION');
      
      // 强制使用IPv4解析
      final addresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      if (addresses.isEmpty) {
        throw Exception('无法解析主机地址: $host');
      }
      
      final request = await _httpClient.openUrl(method, uri);
      request.headers.set('Content-Type', 'application/json');
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }
      
      if (body != null) {
        request.write(body);
      }
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      
      logger.log('响应状态码: ${response.statusCode}', tag: 'CONNECTION');
      
      if (response.statusCode == 200 || response.statusCode == 206) {
        try {
          return json.decode(responseBody) as Map<String, dynamic>;
        } catch (e) {
          return {'success': true, 'data': responseBody};
        }
      } else {
        try {
          return json.decode(responseBody) as Map<String, dynamic>;
        } catch (e) {
          return {
            'success': false,
            'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}'
          };
        }
      }
    } catch (e, stackTrace) {
      logger.logError('请求失败: $method $path', error: e, stackTrace: stackTrace);
      logger.log('连接错误详情: $e', tag: 'CONNECTION');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 测试连接（完全使用WebSocket）
  Future<bool> ping() async {
    try {
      logger.logCommand('ping', details: '测试服务器连接（WebSocket）');
      
      // 如果WebSocket未连接，先尝试连接
      if (_webSocketChannel == null) {
        try {
          await connectWebSocket();
        } catch (e) {
          logger.log('WebSocket连接失败: $e', tag: 'CONNECTION');
          logger.logCommandResponse('ping', success: false, error: 'WebSocket连接失败: $e');
          return false;
        }
      }
      
      // 使用WebSocket ping
      if (_webSocketChannel == null) {
        logger.logCommandResponse('ping', success: false, error: 'WebSocket未连接');
        return false;
      }
      
      try {
        logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'ping'});
        final result = await _sendWebSocketRequest('ping', {});
        final success = result['success'] == true;
        logger.logCommandResponse('ping', success: success, result: result);
        return success;
      } catch (e) {
        logger.log('WebSocket ping失败: $e', tag: 'CONNECTION');
        logger.logCommandResponse('ping', success: false, error: e.toString());
        // WebSocket ping失败，重置连接状态
        _webSocketChannel = null;
        _useWebSocket = false;
        return false;
      }
    } catch (e, stackTrace) {
      logger.logError('Ping失败', error: e, stackTrace: stackTrace);
      logger.log('连接错误详情: $e', tag: 'CONNECTION');
      logger.logCommandResponse('ping', success: false, error: e.toString());
      return false;
    }
  }

  // 拍照（完全使用WebSocket）
  Future<Map<String, dynamic>> capture() async {
    try {
      logger.logCommand('capture', details: '拍照指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'capture'});
      final result = await _sendWebSocketRequest('capture', {});
      logger.logCommandResponse('capture', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('拍照请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('capture', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 开始录像（完全使用WebSocket）
  Future<Map<String, dynamic>> startRecording() async {
    try {
      logger.logCommand('startRecording', details: '开始录像指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'startRecording'});
      final result = await _sendWebSocketRequest('startRecording', {});
      logger.logCommandResponse('startRecording', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('开始录像请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('startRecording', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 停止录像（完全使用WebSocket）
  Future<Map<String, dynamic>> stopRecording() async {
    try {
      logger.logCommand('stopRecording', details: '停止录像指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'stopRecording'});
      final result = await _sendWebSocketRequest('stopRecording', {});
      logger.logCommandResponse('stopRecording', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('停止录像请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('stopRecording', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取文件列表（支持分页和增量获取，完全使用WebSocket）
  /// [page] 页码，从1开始
  /// [pageSize] 每页大小
  /// [since] 增量获取：只获取该时间之后新增/修改的文件（时间戳，毫秒）
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
      
      logger.logCommand('getFileList', details: '获取文件列表指令${params.isNotEmpty ? ' ($params)' : ''}');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getFiles', ...params});
      final result = await _sendWebSocketRequest('getFiles', params);
      
      if (result['success']) {
        // 将JSON转换为FileInfo对象
        result['pictures'] = (result['pictures'] as List?)
            ?.map((json) => FileInfo.fromJson(json))
            .toList() ?? [];
        result['videos'] = (result['videos'] as List?)
            ?.map((json) => FileInfo.fromJson(json))
            .toList() ?? [];
      }
      
      logger.logCommandResponse('getFileList', success: result['success'] == true, result: {
        'pictures_count': (result['pictures'] as List?)?.length ?? 0,
        'videos_count': (result['videos'] as List?)?.length ?? 0,
        'total': result['total'],
        'page': result['page'],
        'hasMore': result['hasMore'],
      }, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取文件列表失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getFileList', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 删除文件（完全使用WebSocket）
  Future<Map<String, dynamic>> deleteFile(String remotePath) async {
    try {
      logger.logCommand('deleteFile', params: {'path': remotePath}, details: '删除文件指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'deleteFile', 'path': remotePath});
      final result = await _sendWebSocketRequest('deleteFile', {'path': remotePath});
      logger.logCommandResponse('deleteFile', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('删除文件失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('deleteFile', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 切换文件星标状态（完全使用WebSocket）
  Future<Map<String, dynamic>> toggleStarred(String remotePath) async {
    try {
      logger.logCommand('toggleStarred', params: {'path': remotePath}, details: '切换文件星标状态');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'toggleStarred', 'path': remotePath});
      final result = await _sendWebSocketRequest('toggleStarred', {'path': remotePath});
      logger.logCommandResponse('toggleStarred', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('切换文件星标状态失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('toggleStarred', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取设置状态（完全使用WebSocket）
  Future<Map<String, dynamic>> getSettingsStatus() async {
    try {
      logger.logCommand('getSettingsStatus', details: '获取设置状态指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getStatus'});
      final result = await _sendWebSocketRequest('getStatus', {});
      logger.logCommandResponse('getSettingsStatus', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设置状态失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getSettingsStatus', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 更新设置（完全使用WebSocket）
  Future<Map<String, dynamic>> updateSettings(CameraSettings settings) async {
    try {
      logger.logCommand('updateSettings', params: settings.toJson(), details: '更新相机设置');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'updateSettings', ...settings.toJson()});
      final result = await _sendWebSocketRequest('updateSettings', settings.toJson());
      logger.logCommandResponse('updateSettings', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('更新设置失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('updateSettings', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 设置方向锁定状态（完全使用WebSocket）
  Future<Map<String, dynamic>> setOrientationLock(bool locked) async {
    try {
      logger.logCommand('setOrientationLock', params: {'locked': locked}, details: '设置方向锁定: $locked');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'setOrientationLock', 'locked': locked});
      final result = await _sendWebSocketRequest('setOrientationLock', {'locked': locked});
      logger.logCommandResponse('setOrientationLock', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('设置方向锁定失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('setOrientationLock', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 设置锁定状态下的旋转角度（完全使用WebSocket）
  Future<Map<String, dynamic>> setLockedRotationAngle(int angle) async {
    try {
      logger.logCommand('setLockedRotationAngle', params: {'angle': angle}, details: '设置锁定旋转角度: $angle');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'setLockedRotationAngle', 'angle': angle});
      final result = await _sendWebSocketRequest('setLockedRotationAngle', {'angle': angle});
      logger.logCommandResponse('setLockedRotationAngle', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('设置锁定旋转角度失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('setLockedRotationAngle', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取当前设置（完全使用WebSocket）
  Future<Map<String, dynamic>> getSettings() async {
    try {
      logger.logCommand('getSettings', details: '获取相机设置指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getSettings'});
      final result = await _sendWebSocketRequest('getSettings', {});
      
      if (result['success'] && result['settings'] != null) {
        // 转换Map类型，确保是Map<String, dynamic>
        final settingsMap = result['settings'];
        if (settingsMap is Map) {
          result['settings'] = CameraSettings.fromJson(_convertMap(settingsMap));
        } else {
          logger.logError('设置数据格式错误', error: Exception('settings不是Map类型: ${settingsMap.runtimeType}'));
        }
      }
      
      logger.logCommandResponse('getSettings', success: result['success'] == true, result: result['settings'], error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设置失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getSettings', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取预览流URL
  String getPreviewStreamUrl() {
    return '$baseUrl/preview/stream';
  }

  // 获取指定相机的能力信息（完全使用WebSocket）
  Future<Map<String, dynamic>> getCameraCapabilities(String cameraId) async {
    try {
      logger.logCommand('getCameraCapabilities', params: {'cameraId': cameraId}, details: '获取相机能力信息');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getCameraCapabilities', 'cameraId': cameraId});
      final result = await _sendWebSocketRequest('getCameraCapabilities', {'cameraId': cameraId});
      logger.logCommandResponse('getCameraCapabilities', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取相机能力信息失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getCameraCapabilities', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取所有相机的能力信息（完全使用WebSocket）
  Future<Map<String, dynamic>> getAllCameraCapabilities() async {
    try {
      logger.logCommand('getAllCameraCapabilities', details: '获取所有相机能力信息');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getAllCameraCapabilities'});
      final result = await _sendWebSocketRequest('getAllCameraCapabilities', {});
      logger.logCommandResponse('getAllCameraCapabilities', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取所有相机能力信息失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getAllCameraCapabilities', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取设备信息（完全使用WebSocket）
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      logger.logCommand('getDeviceInfo', details: '获取设备信息');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getDeviceInfo'});
      final result = await _sendWebSocketRequest('getDeviceInfo', {});
      logger.logCommandResponse('getDeviceInfo', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设备信息失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getDeviceInfo', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 注册设备（完全使用WebSocket）
  Future<Map<String, dynamic>> registerDevice(String deviceModel) async {
    try {
      logger.logCommand('registerDevice', params: {'deviceModel': deviceModel}, details: '注册设备');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'registerDevice', 'deviceModel': deviceModel});
      final result = await _sendWebSocketRequest('registerDevice', {'deviceModel': deviceModel});
      logger.logCommandResponse('registerDevice', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('注册设备失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('registerDevice', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取文件下载URL
  String getFileDownloadUrl(String remotePath) {
    return '$baseUrl/file/download?path=${Uri.encodeComponent(remotePath)}';
  }

  // 获取缩略图URL（支持照片和视频）
  String getThumbnailUrl(String remotePath, bool isVideo) {
    return '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remotePath)}&type=${isVideo ? 'video' : 'image'}';
  }

  // 下载缩略图（支持照片和视频）
  Future<Uint8List?> downloadThumbnail(String remotePath, bool isVideo) async {
    try {
      final uri = Uri.parse(getThumbnailUrl(remotePath, isVideo));
      final request = await _httpClient.getUrl(uri);
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
}

