import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/camera_settings.dart';
import '../models/file_info.dart';
import '../models/connection_error.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'version_compatibility_service.dart';

class ApiService {
  final String baseUrl;
  final String host;
  final int port;
  final ClientLoggerService logger = ClientLoggerService();
  final VersionService _versionService = VersionService();
  final VersionCompatibilityService _versionCompatibilityService =
      VersionCompatibilityService();
  late final HttpClient _httpClient;

  // WebSocket连接管理
  WebSocketChannel? _webSocketChannel;
  StreamSubscription? _webSocketSubscription;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _messageIdCounter = 0;
  bool _useWebSocket = true; // 是否使用WebSocket（默认true）

  // 存储最后一次连接错误
  ConnectionError? _lastConnectionError;

  // WebSocket通知流（用于监听服务器推送的通知）
  // 注意：这个stream会与_handleWebSocketMessage共享同一个stream，所以需要创建一个广播stream
  StreamController<Map<String, dynamic>>? _notificationController;

  Stream<Map<String, dynamic>>? get webSocketNotifications {
    if (_webSocketChannel == null) {
      return null;
    }
    // 如果还没有创建通知控制器，创建一个广播stream
    _notificationController ??=
        StreamController<Map<String, dynamic>>.broadcast();
    return _notificationController!.stream;
  }

  ApiService({
    required String host,
    required int port,
  })  : baseUrl = 'http://$host:$port',
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

  // 认证预检查：在连接WebSocket之前进行认证检查（版本检查、用户认证等）
  Future<ConnectionError?> authenticatePrecheck() async {
    try {
      // 获取客户端版本号
      final clientVersion = await _versionService.getVersion();

      logger.log('执行认证预检查 (客户端版本: $clientVersion)', tag: 'AUTH');

      // 调用认证预检查端点
      final httpUri =
          Uri.parse('$baseUrl/auth/precheck').replace(queryParameters: {
        'clientVersion': clientVersion,
      });
      final request = await _httpClient.getUrl(httpUri);
      await _addVersionHeader(request);
      final response = await request.close();

      if (response.statusCode == 200) {
        // 认证通过
        try {
          final responseBody = await response.transform(utf8.decoder).join();
          final responseData =
              json.decode(responseBody) as Map<String, dynamic>?;
          if (responseData != null && responseData['success'] == true) {
            final serverVersion = responseData['serverVersion'] as String?;
            logger.log('认证预检查通过 (服务器版本: $serverVersion)', tag: 'AUTH');
            _lastConnectionError = null; // 清除之前的错误
            return null; // 成功
          }
        } catch (e) {
          logger.logError('解析认证预检查响应失败', error: e);
        }
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        // 认证失败，解析错误响应
        ConnectionError connectionError;
        try {
          final responseBody = await response.transform(utf8.decoder).join();
          final errorData = json.decode(responseBody) as Map<String, dynamic>?;
          if (errorData != null) {
            connectionError = ConnectionError.fromServerResponse(errorData);
            connectionError = ConnectionError(
              code: connectionError.code,
              message: connectionError.message,
              details: connectionError.details,
              minRequiredVersion: connectionError.minRequiredVersion,
              clientVersion: clientVersion,
              serverVersion: connectionError.serverVersion,
            );
          } else {
            connectionError = ConnectionError(
              code: response.statusCode == 403
                  ? ConnectionErrorCode.versionIncompatible
                  : ConnectionErrorCode.authenticationFailed,
              message: '认证失败',
              clientVersion: clientVersion,
            );
          }
        } catch (e) {
          logger.logError('解析认证失败响应失败', error: e);
          connectionError = ConnectionError(
            code: response.statusCode == 403
                ? ConnectionErrorCode.versionIncompatible
                : ConnectionErrorCode.authenticationFailed,
            message: '认证失败',
            details: e.toString(),
            clientVersion: clientVersion,
          );
        }

        _lastConnectionError = connectionError;
        logger.log('认证预检查失败: ${connectionError.message}', tag: 'AUTH');
        return connectionError;
      } else {
        // 其他HTTP错误
        final connectionError = ConnectionError(
          code: ConnectionErrorCode.serverError,
          message: '服务器错误: HTTP ${response.statusCode}',
          clientVersion: clientVersion,
        );
        _lastConnectionError = connectionError;
        logger.log('认证预检查失败: ${connectionError.message}', tag: 'AUTH');
        return connectionError;
      }
    } catch (e, stackTrace) {
      logger.logError('认证预检查异常', error: e, stackTrace: stackTrace);
      final connectionError = ConnectionError.fromException(e);
      _lastConnectionError = connectionError;
      return connectionError;
    }

    // 默认返回未知错误
    final connectionError = ConnectionError(
      code: ConnectionErrorCode.unknown,
      message: '认证预检查失败：未知错误',
    );
    _lastConnectionError = connectionError;
    return connectionError;
  }

  // 连接WebSocket
  Future<void> connectWebSocket() async {
    if (_webSocketChannel != null) {
      return; // 已经连接
    }

    try {
      // 获取客户端版本号
      final clientVersion = await _versionService.getVersion();

      // 先进行认证预检查（版本检查、用户认证等）
      logger.log('开始认证预检查...', tag: 'WEBSOCKET');
      final precheckError = await authenticatePrecheck();

      if (precheckError != null) {
        // 认证预检查失败，不尝试连接WebSocket
        logger.log('认证预检查失败，取消WebSocket连接: ${precheckError.message}',
            tag: 'WEBSOCKET');
        _handleConnectionFailure(
          precheckError.message,
          isAuthFailure: precheckError.code ==
                  ConnectionErrorCode.versionIncompatible ||
              precheckError.code == ConnectionErrorCode.authenticationFailed,
          minRequiredVersion: precheckError.minRequiredVersion,
        );
        return;
      }

      // 认证预检查通过，继续连接WebSocket
      logger.log('认证预检查通过，开始连接WebSocket...', tag: 'WEBSOCKET');

      final wsUrl = baseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      // 在URL查询参数中包含客户端版本号
      final uri = Uri.parse('$wsUrl/ws').replace(queryParameters: {
        'clientVersion': clientVersion,
      });
      logger.log('连接WebSocket: $uri (客户端版本: $clientVersion)', tag: 'WEBSOCKET');

      // 存储clientVersion供错误处理使用
      final clientVersionForError = clientVersion;

      // 创建通知控制器（如果还没有创建）
      _notificationController ??=
          StreamController<Map<String, dynamic>>.broadcast();

      // 尝试连接WebSocket，设置超时
      _webSocketChannel = WebSocketChannel.connect(uri);

      // 使用Completer来跟踪连接状态
      final connectionCompleter = Completer<bool>();
      bool connectionEstablished = false;
      String? connectionError;
      bool isAuthFailure = false;

      // 监听连接状态
      _webSocketSubscription = _webSocketChannel!.stream.listen(
        (message) {
          if (!connectionEstablished) {
            connectionEstablished = true;
            if (!connectionCompleter.isCompleted) {
              connectionCompleter.complete(true);
            }
          }
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          logger.logError('WebSocket错误', error: error);
          connectionError = error.toString();

          // 检查是否是HTTP错误（403 Forbidden等）
          // 注意：WebSocket升级失败时可能返回500，但实际是403认证失败
          final errorStr = error.toString();

          // 如果已经有_lastConnectionError（从HTTP预检查中获取），优先使用它
          if (_lastConnectionError != null &&
              (_lastConnectionError!.code ==
                      ConnectionErrorCode.versionIncompatible ||
                  _lastConnectionError!.code ==
                      ConnectionErrorCode.authenticationFailed)) {
            logger.log('使用HTTP预检查的错误信息: ${_lastConnectionError!.message}',
                tag: 'WEBSOCKET');
            _handleConnectionFailure(
              _lastConnectionError!.message,
              isAuthFailure: true,
              minRequiredVersion: _lastConnectionError!.minRequiredVersion,
            );
          } else if (errorStr.contains('403') ||
              errorStr.contains('Forbidden') ||
              errorStr.contains('VERSION_INCOMPATIBLE') ||
              (errorStr.contains('500') &&
                  errorStr.contains('was not upgraded to websocket'))) {
            // WebSocket升级失败，可能是版本不兼容
            isAuthFailure = true;
            // 创建版本不兼容错误（如果没有更详细的信息）
            // 注意：由于已经通过预检查，这种情况理论上不应该发生
            // 使用之前存储的clientVersion
            final connectionError = ConnectionError(
              code: ConnectionErrorCode.versionIncompatible,
              message: '版本不兼容：客户端版本 $clientVersionForError 低于服务器要求的最小版本',
              details: errorStr,
              clientVersion: clientVersionForError,
            );
            _lastConnectionError = connectionError;
            _handleConnectionFailure(
              connectionError.message,
              isAuthFailure: true,
            );
          } else {
            final connectionError = ConnectionError.fromException(error);
            _lastConnectionError = connectionError;
            _handleConnectionFailure(connectionError.message);
          }

          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }

          _webSocketChannel = null;
          _notificationController?.close();
          _notificationController = null;
          _useWebSocket = false;
        },
        onDone: () {
          logger.log('WebSocket连接关闭', tag: 'WEBSOCKET');

          // 如果连接立即关闭且没有建立连接，可能是认证失败
          if (!connectionEstablished && connectionError == null) {
            // 检查是否有_lastConnectionError（从HTTP预检查中获取）
            if (_lastConnectionError != null &&
                (_lastConnectionError!.code ==
                        ConnectionErrorCode.versionIncompatible ||
                    _lastConnectionError!.code ==
                        ConnectionErrorCode.authenticationFailed)) {
              _handleConnectionFailure(
                _lastConnectionError!.message,
                isAuthFailure: true,
                minRequiredVersion: _lastConnectionError!.minRequiredVersion,
              );
            } else {
              _handleConnectionFailure(
                '连接被拒绝：可能是版本不兼容或认证失败',
                isAuthFailure: true,
              );
            }
          }

          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }

          _webSocketChannel = null;
          _notificationController?.close();
          _notificationController = null;
          _useWebSocket = false;
        },
        cancelOnError: false,
      );

      // 等待连接建立或超时（2秒，缩短超时时间）
      try {
        final connected = await connectionCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            logger.log('WebSocket连接超时', tag: 'WEBSOCKET');
            // 如果连接立即关闭，可能是认证失败
            if (!connectionEstablished) {
              _handleConnectionFailure(
                '连接超时：服务器可能拒绝了连接（可能是版本不兼容）',
                isAuthFailure: true,
              );
            } else {
              _handleConnectionFailure('连接超时：服务器可能拒绝了连接');
            }
            return false;
          },
        );

        if (connected) {
          logger.log('WebSocket连接成功', tag: 'WEBSOCKET');
        } else {
          // 连接失败，清理资源
          _webSocketChannel?.sink.close();
          _webSocketChannel = null;
          _notificationController?.close();
          _notificationController = null;
          _useWebSocket = false;
        }
      } catch (e) {
        logger.logError('等待WebSocket连接时出错', error: e);
        _handleConnectionFailure('连接失败: $e', isAuthFailure: isAuthFailure);
        _webSocketChannel?.sink.close();
        _webSocketChannel = null;
        _notificationController?.close();
        _notificationController = null;
        _useWebSocket = false;
      }
    } catch (e, stackTrace) {
      logger.logError('WebSocket连接失败', error: e, stackTrace: stackTrace);

      // 获取客户端版本号（用于错误信息）
      String? clientVersion;
      try {
        clientVersion = await _versionService.getVersion();
      } catch (e) {
        logger.logError('获取客户端版本失败', error: e);
      }

      // 检查是否是认证失败
      // 如果已经有_lastConnectionError（从HTTP预检查中获取），使用它
      if (_lastConnectionError != null &&
          (_lastConnectionError!.code ==
                  ConnectionErrorCode.versionIncompatible ||
              _lastConnectionError!.code ==
                  ConnectionErrorCode.authenticationFailed)) {
        _handleConnectionFailure(
          _lastConnectionError!.message,
          isAuthFailure: true,
          minRequiredVersion: _lastConnectionError!.minRequiredVersion,
        );
      } else {
        final errorStr = e.toString();
        final isAuthFailure = errorStr.contains('403') ||
            errorStr.contains('Forbidden') ||
            errorStr.contains('VERSION_INCOMPATIBLE') ||
            (errorStr.contains('500') &&
                errorStr.contains('was not upgraded to websocket'));

        if (isAuthFailure) {
          final connectionError = ConnectionError(
            code: ConnectionErrorCode.versionIncompatible,
            message: clientVersion != null
                ? '版本不兼容：客户端版本 $clientVersion 低于服务器要求的最小版本'
                : '版本不兼容：客户端版本过低',
            details: errorStr,
            clientVersion: clientVersion,
          );
          _lastConnectionError = connectionError;
          _handleConnectionFailure(
            connectionError.message,
            isAuthFailure: true,
          );
        } else {
          final connectionError = ConnectionError.fromException(e);
          _lastConnectionError = connectionError;
          _handleConnectionFailure(connectionError.message);
        }
      }

      _webSocketChannel = null;
      _useWebSocket = false;
    }
  }

  // 处理连接失败
  void _handleConnectionFailure(
    String errorMessage, {
    bool isAuthFailure = false,
    String? minRequiredVersion,
  }) {
    logger.log('WebSocket连接失败: $errorMessage', tag: 'WEBSOCKET');

    // 检查是否是版本不兼容错误
    final isVersionIncompatible = isAuthFailure ||
        errorMessage.contains('版本不兼容') ||
        errorMessage.contains('VERSION_INCOMPATIBLE') ||
        errorMessage.contains('低于服务器要求');

    // 如果没有_lastConnectionError，创建一个
    if (_lastConnectionError == null) {
      _lastConnectionError = ConnectionError(
        code: isVersionIncompatible
            ? ConnectionErrorCode.versionIncompatible
            : ConnectionErrorCode.networkError,
        message: errorMessage,
        minRequiredVersion: minRequiredVersion,
      );
    }

    // 发送连接失败通知（包含完整的ConnectionError信息）
    _notificationController?.add({
      'type': 'notification',
      'event': 'connection_failed',
      'data': {
        'reason':
            isVersionIncompatible ? 'version_incompatible' : 'connection_error',
        'message': errorMessage,
        'isAuthFailure': isAuthFailure,
        if (minRequiredVersion != null)
          'minRequiredVersion': minRequiredVersion,
        'error': _lastConnectionError!.toJson(), // 包含完整的错误信息
      },
    });
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
        // 处理通知消息（如new_files、connected、version_incompatible）
        final event = data['event'] as String?;

        if (event == 'version_incompatible') {
          // 版本不兼容通知
          final notificationData = data['data'] as Map<String, dynamic>?;
          final message = notificationData?['message'] as String? ?? '版本不兼容';
          logger.log('版本不兼容: $message', tag: 'VERSION_COMPAT');
          // 广播版本不兼容通知
          _notificationController?.add(data);
          // 主动断开连接
          disconnectWebSocket();
        } else if (event == 'connected') {
          // 连接成功通知，检查服务器版本
          final notificationData = data['data'] as Map<String, dynamic>?;
          final serverVersion = notificationData?['serverVersion'] as String?;
          if (serverVersion != null) {
            _checkServerVersion(serverVersion);
          }
          // 广播连接通知
          _notificationController?.add(data);
        } else {
          // 其他通知消息
          logger.log('收到WebSocket通知: $data', tag: 'WEBSOCKET');
          _notificationController?.add(data);
        }
      }
    } catch (e) {
      logger.logError('解析WebSocket消息失败', error: e);
    }
  }

  // 检查服务器版本兼容性
  Future<void> _checkServerVersion(String serverVersion) async {
    try {
      final (isCompatible, reason) =
          await _versionCompatibilityService.checkServerVersion(serverVersion);
      if (!isCompatible) {
        logger.log('服务器版本不兼容: $reason', tag: 'VERSION_COMPAT');
        // 发送版本不兼容通知
        _notificationController?.add({
          'type': 'notification',
          'event': 'server_version_incompatible',
          'data': {
            'reason': 'server_version_incompatible',
            'message': reason ?? '服务器版本不兼容',
            'serverVersion': serverVersion,
          },
        });
        // 断开连接
        disconnectWebSocket();
      } else {
        logger.log('服务器版本兼容: $serverVersion', tag: 'VERSION_COMPAT');
      }
    } catch (e, stackTrace) {
      logger.logError('检查服务器版本失败', error: e, stackTrace: stackTrace);
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

  // 通过WebSocket发送请求
  Future<Map<String, dynamic>> _sendWebSocketRequest(
      String action, Map<String, dynamic> params) async {
    if (_webSocketChannel == null) {
      await connectWebSocket();
    }

    if (_webSocketChannel == null) {
      throw Exception('WebSocket未连接');
    }

    final messageId =
        'msg_${++_messageIdCounter}_${DateTime.now().millisecondsSinceEpoch}';
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
      final addresses =
          await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
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
  /// 返回null表示成功，返回ConnectionError表示失败
  Future<ConnectionError?> ping() async {
    try {
      logger.logCommand('ping', details: '测试服务器连接（WebSocket）');

      // 如果WebSocket未连接，先尝试连接
      if (_webSocketChannel == null) {
        try {
          await connectWebSocket();
        } catch (e) {
          logger.log('WebSocket连接失败: $e', tag: 'CONNECTION');
          final error =
              _lastConnectionError ?? ConnectionError.fromException(e);
          logger.logCommandResponse('ping',
              success: false, error: error.message);
          return error;
        }
      }

      // 使用WebSocket ping
      if (_webSocketChannel == null) {
        final error = _lastConnectionError ??
            ConnectionError(
              code: ConnectionErrorCode.networkError,
              message: 'WebSocket未连接',
            );
        logger.logCommandResponse('ping', success: false, error: error.message);
        return error;
      }

      try {
        logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'ping'});
        final result = await _sendWebSocketRequest('ping', {});
        final success = result['success'] == true;
        logger.logCommandResponse('ping', success: success, result: result);

        if (success) {
          _lastConnectionError = null; // 清除错误
          return null; // 成功
        } else {
          final error = ConnectionError(
            code: ConnectionErrorCode.connectionRefused,
            message: result['error'] as String? ?? '连接失败',
          );
          _lastConnectionError = error;
          return error;
        }
      } catch (e) {
        logger.log('WebSocket ping失败: $e', tag: 'CONNECTION');
        final error = ConnectionError.fromException(e);
        _lastConnectionError = error;
        logger.logCommandResponse('ping', success: false, error: error.message);
        // WebSocket ping失败，重置连接状态
        _webSocketChannel = null;
        _useWebSocket = false;
        return error;
      }
    } catch (e, stackTrace) {
      logger.logError('Ping失败', error: e, stackTrace: stackTrace);
      logger.log('连接错误详情: $e', tag: 'CONNECTION');
      final error = ConnectionError.fromException(e);
      _lastConnectionError = error;
      logger.logCommandResponse('ping', success: false, error: error.message);
      return error;
    }
  }

  // 拍照（完全使用WebSocket）
  Future<Map<String, dynamic>> capture() async {
    try {
      logger.logCommand('capture', details: '拍照指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'capture'});
      final result = await _sendWebSocketRequest('capture', {});
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

  // 开始录像（完全使用WebSocket）
  Future<Map<String, dynamic>> startRecording() async {
    try {
      logger.logCommand('startRecording', details: '开始录像指令');
      logger
          .logApiCall('WEBSOCKET', '/ws', params: {'action': 'startRecording'});
      final result = await _sendWebSocketRequest('startRecording', {});
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

  // 停止录像（完全使用WebSocket）
  Future<Map<String, dynamic>> stopRecording() async {
    try {
      logger.logCommand('stopRecording', details: '停止录像指令');
      logger
          .logApiCall('WEBSOCKET', '/ws', params: {'action': 'stopRecording'});
      final result = await _sendWebSocketRequest('stopRecording', {});
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

      logger.logCommand('getFileList',
          details: '获取文件列表指令${params.isNotEmpty ? ' ($params)' : ''}');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'getFiles', ...params});
      final result = await _sendWebSocketRequest('getFiles', params);

      if (result['success']) {
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

  // 删除文件（完全使用WebSocket）
  Future<Map<String, dynamic>> deleteFile(String remotePath) async {
    try {
      logger.logCommand('deleteFile',
          params: {'path': remotePath}, details: '删除文件指令');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'deleteFile', 'path': remotePath});
      final result =
          await _sendWebSocketRequest('deleteFile', {'path': remotePath});
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

  // 切换文件星标状态（完全使用WebSocket）
  Future<Map<String, dynamic>> toggleStarred(String remotePath) async {
    try {
      logger.logCommand('toggleStarred',
          params: {'path': remotePath}, details: '切换文件星标状态');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'toggleStarred', 'path': remotePath});
      final result =
          await _sendWebSocketRequest('toggleStarred', {'path': remotePath});
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

  // 获取设置状态（完全使用WebSocket）
  Future<Map<String, dynamic>> getSettingsStatus() async {
    try {
      logger.logCommand('getSettingsStatus', details: '获取设置状态指令');
      logger.logApiCall('WEBSOCKET', '/ws', params: {'action': 'getStatus'});
      final result = await _sendWebSocketRequest('getStatus', {});
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

  // 更新设置（完全使用WebSocket）
  Future<Map<String, dynamic>> updateSettings(CameraSettings settings) async {
    try {
      logger.logCommand('updateSettings',
          params: settings.toJson(), details: '更新相机设置');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'updateSettings', ...settings.toJson()});
      final result =
          await _sendWebSocketRequest('updateSettings', settings.toJson());
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

  // 设置方向锁定状态（完全使用WebSocket）
  Future<Map<String, dynamic>> setOrientationLock(bool locked) async {
    try {
      logger.logCommand('setOrientationLock',
          params: {'locked': locked}, details: '设置方向锁定: $locked');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'setOrientationLock', 'locked': locked});
      final result =
          await _sendWebSocketRequest('setOrientationLock', {'locked': locked});
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

  // 设置锁定状态下的旋转角度（完全使用WebSocket）
  Future<Map<String, dynamic>> setLockedRotationAngle(int angle) async {
    try {
      logger.logCommand('setLockedRotationAngle',
          params: {'angle': angle}, details: '设置锁定旋转角度: $angle');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'setLockedRotationAngle', 'angle': angle});
      final result = await _sendWebSocketRequest(
          'setLockedRotationAngle', {'angle': angle});
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
          result['settings'] =
              CameraSettings.fromJson(_convertMap(settingsMap));
        } else {
          logger.logError('设置数据格式错误',
              error: Exception('settings不是Map类型: ${settingsMap.runtimeType}'));
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

  // 获取预览流URL
  // 获取预览流URL（包含客户端版本号）
  Future<String> getPreviewStreamUrl() async {
    try {
      final clientVersion = await _versionService.getVersion();
      return '$baseUrl/preview/stream?clientVersion=$clientVersion';
    } catch (e) {
      logger.logError('获取预览流URL失败', error: e);
      // 即使失败也返回基本URL（向后兼容）
      return '$baseUrl/preview/stream';
    }
  }

  // 获取单帧预览（用于初始化预览窗口）
  Future<Uint8List?> getSinglePreviewFrame() async {
    try {
      logger.logApiCall('HTTP', '/preview/stream');
      final clientVersion = await _versionService.getVersion();
      final url = '$baseUrl/preview/stream?clientVersion=$clientVersion';

      final request = await _httpClient.getUrl(Uri.parse(url));
      request.headers.set(
          'User-Agent', 'HelloKnightRCC/${await _versionService.getVersion()}');

      final response = await request.close();

      if (response.statusCode != 200) {
        logger.logError('获取单帧预览失败: HTTP ${response.statusCode}');
        return null;
      }

      // 读取纯JPEG流的第一帧
      // JPEG格式：以0xFF 0xD8开始，以0xFF 0xD9结束
      final List<int> buffer = [];
      bool foundStart = false;
      int maxBytesToRead = 5 * 1024 * 1024; // 最多读取5MB
      int totalBytesRead = 0;

      await for (final chunk in response) {
        buffer.addAll(chunk);
        totalBytesRead += chunk.length;

        // 限制读取大小
        if (totalBytesRead > maxBytesToRead) {
          logger.logError('获取单帧预览失败: 读取数据过多 (${totalBytesRead} 字节)');
          return null;
        }

        // 查找JPEG开始标记（0xFF 0xD8）
        if (!foundStart) {
          for (int i = 0; i < buffer.length - 1; i++) {
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
              foundStart = true;
              // 移除开始标记之前的数据
              if (i > 0) {
                buffer.removeRange(0, i);
              }
              logger.log('找到JPEG开始标记', tag: 'PREVIEW');
              break;
            }
          }
          if (!foundStart) {
            // 如果缓冲区超过10KB还没找到开始标记，可能格式不对
            if (buffer.length > 10 * 1024) {
              logger
                  .logError('获取单帧预览失败: 未找到JPEG开始标记 (已读取 ${buffer.length} 字节)');
              return null;
            }
            continue;
          }
        }

        // 已找到开始标记，查找结束标记（0xFF 0xD9）
        if (foundStart && buffer.length >= 2) {
          for (int i = buffer.length - 2; i >= 0; i--) {
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
              // 找到完整的JPEG帧
              final jpegData = Uint8List.fromList(buffer.sublist(0, i + 2));
              logger.log('成功获取单帧预览，大小: ${jpegData.length} 字节', tag: 'PREVIEW');
              return jpegData;
            }
          }
        }

        // 如果缓冲区太大但还没找到完整帧，可能有问题
        if (buffer.length > 2 * 1024 * 1024) {
          logger.logError('获取单帧预览失败: 缓冲区过大但未找到完整帧 (${buffer.length} 字节)');
          return null;
        }
      }

      logger.logError('获取单帧预览失败: 流结束但未找到完整JPEG帧 (已读取 ${buffer.length} 字节)');
      return null;
    } catch (e, stackTrace) {
      logger.logError('获取单帧预览失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // 获取指定相机的能力信息（完全使用WebSocket）
  Future<Map<String, dynamic>> getCameraCapabilities(String cameraId) async {
    try {
      logger.logCommand('getCameraCapabilities',
          params: {'cameraId': cameraId}, details: '获取相机能力信息');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'getCameraCapabilities', 'cameraId': cameraId});
      final result = await _sendWebSocketRequest(
          'getCameraCapabilities', {'cameraId': cameraId});
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

  // 获取所有相机的能力信息（完全使用WebSocket）
  Future<Map<String, dynamic>> getAllCameraCapabilities() async {
    try {
      logger.logCommand('getAllCameraCapabilities', details: '获取所有相机能力信息');
      logger.logApiCall('WEBSOCKET', '/ws',
          params: {'action': 'getAllCameraCapabilities'});
      final result =
          await _sendWebSocketRequest('getAllCameraCapabilities', {});
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

  // 获取设备信息（完全使用WebSocket）
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      logger.logCommand('getDeviceInfo', details: '获取设备信息');
      logger
          .logApiCall('WEBSOCKET', '/ws', params: {'action': 'getDeviceInfo'});
      final result = await _sendWebSocketRequest('getDeviceInfo', {});
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

  // 注册设备（完全使用WebSocket，包含客户端版本信息）
  Future<Map<String, dynamic>> registerDevice(String deviceModel) async {
    try {
      // 获取客户端版本号
      final clientVersion = await _versionService.getVersion();

      logger.logCommand('registerDevice',
          params: {'deviceModel': deviceModel, 'clientVersion': clientVersion},
          details: '注册设备');
      logger.logApiCall('WEBSOCKET', '/ws', params: {
        'action': 'registerDevice',
        'deviceModel': deviceModel,
        'clientVersion': clientVersion
      });
      final result = await _sendWebSocketRequest('registerDevice', {
        'deviceModel': deviceModel,
        'clientVersion': clientVersion,
      });
      logger.logCommandResponse('registerDevice',
          success: result['success'] == true,
          result: result,
          error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('注册设备失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('registerDevice',
          success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取文件下载URL
  String getFileDownloadUrl(String remotePath) {
    return '$baseUrl/file/download?path=${Uri.encodeComponent(remotePath)}';
  }

  // 获取缩略图URL（支持照片和视频，包含客户端版本号）
  Future<String> getThumbnailUrl(String remotePath, bool isVideo) async {
    try {
      final clientVersion = await _versionService.getVersion();
      return '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remotePath)}&type=${isVideo ? 'video' : 'image'}&clientVersion=$clientVersion';
    } catch (e) {
      logger.logError('获取缩略图URL失败', error: e);
      // 即使失败也返回基本URL（向后兼容）
      return '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remotePath)}&type=${isVideo ? 'video' : 'image'}';
    }
  }

  // 为HTTP请求添加版本头
  Future<void> _addVersionHeader(HttpClientRequest request) async {
    try {
      final clientVersion = await _versionService.getVersion();
      request.headers.add('X-Client-Version', clientVersion);
    } catch (e) {
      logger.logError('添加版本头失败', error: e);
      // 即使失败也继续，不阻塞请求
    }
  }

  // 下载缩略图（支持照片和视频）
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
}
