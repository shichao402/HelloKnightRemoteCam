import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/connection_error.dart';
import 'logger_service.dart';
import 'version_service.dart';
import 'version_compatibility_service.dart';

/// 连接状态枚举
enum ConnectionState {
  /// 未连接
  disconnected,

  /// 正在连接（包括认证预检查和WebSocket握手）
  connecting,

  /// 已连接（WebSocket已建立，但尚未注册设备）
  connected,

  /// 已注册（设备已注册，可以正常使用）
  registered,

  /// 正在断开连接
  disconnecting,
  
  /// 正在重连
  reconnecting,
}

/// 连接状态变化事件
class ConnectionStateChange {
  final ConnectionState oldState;
  final ConnectionState newState;
  final ConnectionError? error;
  final Map<String, dynamic>? data;

  ConnectionStateChange({
    required this.oldState,
    required this.newState,
    this.error,
    this.data,
  });

  @override
  String toString() =>
      'ConnectionStateChange($oldState -> $newState${error != null ? ', error: ${error!.message}' : ''})';
}

/// WebSocket连接管理器
/// 
/// 职责：
/// - 管理连接生命周期（连接、断开、重连）
/// - 维护连接状态（状态机）
/// - 处理认证预检查
/// - 处理心跳
/// - 处理服务器通知
/// 
/// 不负责：
/// - 具体的业务逻辑（由 ApiService 处理）
class WebSocketConnection {
  final String host;
  final int port;
  final ClientLoggerService _logger = ClientLoggerService();
  final VersionService _versionService = VersionService();
  final VersionCompatibilityService _versionCompatibilityService =
      VersionCompatibilityService();

  // 连接状态
  ConnectionState _state = ConnectionState.disconnected;
  ConnectionState get state => _state;

  // 连接错误
  ConnectionError? _lastError;
  ConnectionError? get lastError => _lastError;

  // WebSocket通道
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // 状态变化流
  final _stateController = StreamController<ConnectionStateChange>.broadcast();
  Stream<ConnectionStateChange> get stateStream => _stateController.stream;

  // 消息流（用于接收服务器消息）
  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // 通知流（用于接收服务器推送通知）
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;

  // 待处理的请求
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _messageIdCounter = 0;

  // 心跳定时器
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 1);
  static const Duration _heartbeatTimeout = Duration(seconds: 5);

  // 自动重连配置
  bool _autoReconnect = true;
  bool get autoReconnect => _autoReconnect;
  set autoReconnect(bool value) => _autoReconnect = value;
  
  int _reconnectAttempts = 0;
  int get reconnectAttempts => _reconnectAttempts;
  static const int _maxReconnectAttempts = 20;
  static const Duration _reconnectInterval = Duration(seconds: 3);
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  
  // 记录上次注册的设备型号（用于重连后自动注册）
  String? _lastDeviceModel;

  // 服务器信息（连接成功后获取）
  String? _serverVersion;
  String? get serverVersion => _serverVersion;
  Map<String, dynamic>? _previewSize;
  Map<String, dynamic>? get previewSize => _previewSize;

  WebSocketConnection({
    required this.host,
    required this.port,
  });

  /// 获取基础URL
  String get baseUrl => 'http://$host:$port';
  String get wsUrl => 'ws://$host:$port';

  /// 是否已连接（connected 或 registered 状态）
  bool get isConnected =>
      _state == ConnectionState.connected ||
      _state == ConnectionState.registered;

  /// 是否已注册
  bool get isRegistered => _state == ConnectionState.registered;

  /// 连接到服务器
  /// 
  /// 流程：
  /// 1. 认证预检查（HTTP）
  /// 2. 建立WebSocket连接
  /// 3. 等待服务器确认（connected通知）
  /// 
  /// 返回：null表示成功，ConnectionError表示失败
  Future<ConnectionError?> connect() async {
    if (_state != ConnectionState.disconnected) {
      _logger.log('连接请求被忽略：当前状态为 $_state', tag: 'CONNECTION');
      if (_state == ConnectionState.connected ||
          _state == ConnectionState.registered) {
        return null; // 已经连接
      }
      return ConnectionError(
        code: ConnectionErrorCode.unknown,
        message: '连接正在进行中',
      );
    }

    _setState(ConnectionState.connecting);
    _lastError = null;

    try {
      // 1. 认证预检查
      final precheckError = await _authenticatePrecheck();
      if (precheckError != null) {
        _setError(precheckError);
        _setState(ConnectionState.disconnected);
        return precheckError;
      }

      // 2. 建立WebSocket连接
      final wsError = await _connectWebSocket();
      if (wsError != null) {
        _setError(wsError);
        _setState(ConnectionState.disconnected);
        return wsError;
      }

      // 连接成功，状态已在 _handleConnectedNotification 中更新
      return null;
    } catch (e, stackTrace) {
      _logger.logError('连接失败', error: e, stackTrace: stackTrace);
      final error = ConnectionError.fromException(e);
      _setError(error);
      _setState(ConnectionState.disconnected);
      return error;
    }
  }

  /// 断开连接
  /// 
  /// [cancelAutoReconnect] 是否取消自动重连，默认为 true（主动断开时不重连）
  Future<void> disconnect({bool cancelAutoReconnect = true}) async {
    if (_state == ConnectionState.disconnected ||
        _state == ConnectionState.disconnecting) {
      return;
    }

    // 主动断开时取消自动重连
    if (cancelAutoReconnect) {
      cancelReconnect();
    }

    _setState(ConnectionState.disconnecting);
    _logger.log('开始断开连接', tag: 'CONNECTION');

    try {
      // 停止心跳
      _stopHeartbeat();

      // 完成所有待处理请求
      _failAllPendingRequests('连接已断开');

      // 关闭WebSocket
      await _subscription?.cancel();
      _subscription = null;
      await _channel?.sink.close();
      _channel = null;

      _logger.log('连接已断开', tag: 'CONNECTION');
    } catch (e, stackTrace) {
      _logger.logError('断开连接时出错', error: e, stackTrace: stackTrace);
    } finally {
      _setState(ConnectionState.disconnected);
    }
  }

  /// 发送WebSocket请求
  /// 
  /// 返回服务器响应，如果失败则抛出异常
  Future<Map<String, dynamic>> sendRequest(
    String action,
    Map<String, dynamic> params,
  ) async {
    if (!isConnected) {
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

      _channel!.sink.add(request);

      // 设置超时（10秒）
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingRequests.remove(messageId);
          throw TimeoutException('请求超时: $action');
        },
      );
    } catch (e) {
      _pendingRequests.remove(messageId);
      rethrow;
    }
  }

  /// 注册设备（设置独占连接）
  Future<ConnectionError?> registerDevice(String deviceModel) async {
    if (_state != ConnectionState.connected) {
      return ConnectionError(
        code: ConnectionErrorCode.unknown,
        message: '无法注册设备：当前状态为 $_state',
      );
    }

    try {
      final clientVersion = await _versionService.getVersion();
      final result = await sendRequest('registerDevice', {
        'deviceModel': deviceModel,
        'clientVersion': clientVersion,
      });

      if (result['success'] == true) {
        _lastDeviceModel = deviceModel; // 记录设备型号用于重连
        _setState(ConnectionState.registered);
        _logger.log('设备注册成功: $deviceModel', tag: 'CONNECTION');
        return null;
      } else {
        final error = ConnectionError(
          code: ConnectionErrorCode.connectionRefused,
          message: result['error'] as String? ?? '设备注册失败',
        );
        _setError(error);
        return error;
      }
    } catch (e, stackTrace) {
      _logger.logError('设备注册失败', error: e, stackTrace: stackTrace);
      final error = ConnectionError.fromException(e);
      _setError(error);
      return error;
    }
  }

  /// 取消重连
  void cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectAttempts = 0;
    _logger.log('重连已取消', tag: 'RECONNECT');
  }

  /// 释放资源
  void dispose() {
    cancelReconnect();
    _stopHeartbeat();
    _failAllPendingRequests('连接已释放');
    _subscription?.cancel();
    _channel?.sink.close();
    _stateController.close();
    _messageController.close();
    _notificationController.close();
  }

  // ==================== 私有方法 ====================

  /// 设置状态
  void _setState(ConnectionState newState) {
    if (_state == newState) return;

    final oldState = _state;
    _state = newState;
    _logger.log('连接状态变化: $oldState -> $newState', tag: 'CONNECTION');

    _stateController.add(ConnectionStateChange(
      oldState: oldState,
      newState: newState,
      error: _lastError,
    ));
  }

  /// 设置错误
  void _setError(ConnectionError error) {
    _lastError = error;
    _logger.log('连接错误: ${error.message}', tag: 'CONNECTION');
  }

  /// 认证预检查
  Future<ConnectionError?> _authenticatePrecheck() async {
    try {
      final clientVersion = await _versionService.getVersion();
      _logger.log('执行认证预检查 (客户端版本: $clientVersion)', tag: 'AUTH');

      final uri = Uri.parse('$baseUrl/auth/precheck').replace(queryParameters: {
        'clientVersion': clientVersion,
      });

      final httpClient = _createHttpClient();
      try {
        final request = await httpClient.getUrl(uri);
        request.headers.add('X-Client-Version', clientVersion);
        final response = await request.close();

        if (response.statusCode == 200) {
          final responseBody =
              await response.transform(const Utf8Decoder()).join();
          final responseData =
              json.decode(responseBody) as Map<String, dynamic>?;

          if (responseData != null && responseData['success'] == true) {
            final serverVersion = responseData['serverVersion'] as String?;
            _serverVersion = serverVersion;
            _logger.log('认证预检查通过 (服务器版本: $serverVersion)', tag: 'AUTH');

            // 检查服务器版本兼容性
            if (serverVersion != null) {
              final (isCompatible, reason) = await _versionCompatibilityService
                  .checkServerVersion(serverVersion);
              if (!isCompatible) {
                return ConnectionError(
                  code: ConnectionErrorCode.serverVersionTooLow,
                  message: reason ?? '服务器版本过低',
                  serverVersion: serverVersion,
                  minRequiredVersion:
                      await _versionCompatibilityService.getMinServerVersion(),
                  clientVersion: clientVersion,
                );
              }
            }

            return null; // 成功
          }
        } else if (response.statusCode == 403 || response.statusCode == 401) {
          final responseBody =
              await response.transform(const Utf8Decoder()).join();
          final errorData =
              json.decode(responseBody) as Map<String, dynamic>?;
          if (errorData != null) {
            return ConnectionError.fromServerResponse(errorData);
          }
          return ConnectionError(
            code: response.statusCode == 403
                ? ConnectionErrorCode.versionIncompatible
                : ConnectionErrorCode.authenticationFailed,
            message: '认证失败',
            clientVersion: clientVersion,
          );
        }

        return ConnectionError(
          code: ConnectionErrorCode.serverError,
          message: '服务器错误: HTTP ${response.statusCode}',
          clientVersion: clientVersion,
        );
      } finally {
        httpClient.close();
      }
    } catch (e, stackTrace) {
      _logger.logError('认证预检查异常', error: e, stackTrace: stackTrace);
      return ConnectionError.fromException(e);
    }
  }

  /// 创建HTTP客户端
  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    client.idleTimeout = const Duration(seconds: 5);
    return client;
  }

  /// 建立WebSocket连接
  Future<ConnectionError?> _connectWebSocket() async {
    try {
      final clientVersion = await _versionService.getVersion();
      final uri = Uri.parse('$wsUrl/ws').replace(queryParameters: {
        'clientVersion': clientVersion,
      });

      _logger.log('连接WebSocket: $uri', tag: 'WEBSOCKET');

      _channel = WebSocketChannel.connect(uri);

      // 使用Completer来跟踪连接状态
      final connectionCompleter = Completer<ConnectionError?>();
      bool connectionEstablished = false;

      _subscription = _channel!.stream.listen(
        (message) {
          if (!connectionEstablished) {
            connectionEstablished = true;
          }
          _handleMessage(message, connectionCompleter);
        },
        onError: (error) {
          _logger.logError('WebSocket错误', error: error);
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(ConnectionError.fromException(error));
          }
          _handleDisconnect();
        },
        onDone: () {
          _logger.log('WebSocket连接关闭', tag: 'WEBSOCKET');
          if (!connectionCompleter.isCompleted) {
            if (!connectionEstablished) {
              connectionCompleter.complete(ConnectionError(
                code: ConnectionErrorCode.connectionRefused,
                message: '连接被服务器关闭',
              ));
            } else {
              connectionCompleter.complete(null);
            }
          }
          _handleDisconnect();
        },
        cancelOnError: false,
      );

      // 等待连接建立或超时（3秒）
      final result = await connectionCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _logger.log('WebSocket连接超时', tag: 'WEBSOCKET');
          return ConnectionError(
            code: ConnectionErrorCode.connectionTimeout,
            message: '连接超时',
          );
        },
      );

      if (result != null) {
        // 连接失败，清理资源
        await _subscription?.cancel();
        _subscription = null;
        await _channel?.sink.close();
        _channel = null;
      } else {
        // 连接成功，启动心跳
        _startHeartbeat();
      }

      return result;
    } catch (e, stackTrace) {
      _logger.logError('WebSocket连接失败', error: e, stackTrace: stackTrace);
      return ConnectionError.fromException(e);
    }
  }

  /// 处理WebSocket消息
  void _handleMessage(
      dynamic message, Completer<ConnectionError?>? connectionCompleter) {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      final messageType = data['type'] as String?;

      if (messageType == 'response') {
        _handleResponse(data);
      } else if (messageType == 'notification') {
        _handleNotification(data, connectionCompleter);
      }

      // 广播原始消息
      _messageController.add(data);
    } catch (e) {
      _logger.logError('解析WebSocket消息失败', error: e);
    }
  }

  /// 处理响应消息
  void _handleResponse(Map<String, dynamic> data) {
    final messageId = data['id'] as String?;
    if (messageId != null && _pendingRequests.containsKey(messageId)) {
      final completer = _pendingRequests.remove(messageId)!;
      if (data['success'] == true) {
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
  }

  /// 处理通知消息
  void _handleNotification(
      Map<String, dynamic> data, Completer<ConnectionError?>? connectionCompleter) {
    final event = data['event'] as String?;
    final notificationData = data['data'] as Map<String, dynamic>?;

    switch (event) {
      case 'connected':
        _handleConnectedNotification(notificationData, connectionCompleter);
        break;
      case 'version_incompatible':
        _handleVersionIncompatibleNotification(notificationData);
        break;
      case 'connection_rejected':
        _handleConnectionRejectedNotification(notificationData, connectionCompleter);
        break;
      default:
        // 其他通知直接广播
        _notificationController.add(data);
    }
  }

  /// 处理连接成功通知
  void _handleConnectedNotification(
      Map<String, dynamic>? data, Completer<ConnectionError?>? connectionCompleter) {
    _serverVersion = data?['serverVersion'] as String?;
    _previewSize = data?['previewSize'] as Map<String, dynamic>?;

    _logger.log(
        '收到连接确认 (服务器版本: $_serverVersion, 预览尺寸: $_previewSize)',
        tag: 'WEBSOCKET');

    _setState(ConnectionState.connected);

    // 完成连接等待
    if (connectionCompleter != null && !connectionCompleter.isCompleted) {
      connectionCompleter.complete(null);
    }

    // 广播通知
    _notificationController.add({
      'type': 'notification',
      'event': 'connected',
      'data': data,
    });
  }

  /// 处理版本不兼容通知
  void _handleVersionIncompatibleNotification(Map<String, dynamic>? data) {
    final message = data?['message'] as String? ?? '版本不兼容';
    _logger.log('版本不兼容: $message', tag: 'VERSION_COMPAT');

    final error = ConnectionError(
      code: ConnectionErrorCode.versionIncompatible,
      message: message,
    );
    _setError(error);

    // 广播通知
    _notificationController.add({
      'type': 'notification',
      'event': 'version_incompatible',
      'data': data,
    });

    // 断开连接
    disconnect();
  }

  /// 处理连接被拒绝通知
  void _handleConnectionRejectedNotification(
      Map<String, dynamic>? data, Completer<ConnectionError?>? connectionCompleter) {
    final reason = data?['reason'] as String? ?? 'unknown';
    final message = data?['message'] as String? ?? '连接被拒绝';
    _logger.log('连接被拒绝: $reason - $message', tag: 'CONNECTION');

    final error = ConnectionError(
      code: ConnectionErrorCode.connectionRejected,
      message: message,
    );
    _setError(error);

    // 完成连接等待（失败）
    if (connectionCompleter != null && !connectionCompleter.isCompleted) {
      connectionCompleter.complete(error);
    }

    // 完成所有待处理请求
    _failAllPendingRequests(message);

    // 广播通知
    _notificationController.add({
      'type': 'notification',
      'event': 'connection_rejected',
      'data': data,
    });

    // 断开连接
    disconnect();
  }

  /// 处理断开连接
  void _handleDisconnect() {
    if (_state == ConnectionState.disconnected ||
        _state == ConnectionState.disconnecting) {
      return;
    }

    _stopHeartbeat();
    _failAllPendingRequests('连接已断开');
    _channel = null;
    _subscription = null;
    
    // 检查是否需要自动重连
    // 不重连的情况：
    // 1. 禁用了自动重连
    // 2. 认证失败（版本不兼容等）
    // 3. 已经在重连中
    final shouldReconnect = _autoReconnect && 
        !_isAuthFailure(_lastError) &&
        !_isReconnecting;
    
    if (shouldReconnect) {
      _startReconnect();
    } else {
      _setState(ConnectionState.disconnected);
    }
  }
  
  /// 检查是否是认证失败错误（不应该重连）
  bool _isAuthFailure(ConnectionError? error) {
    if (error == null) return false;
    return error.code == ConnectionErrorCode.versionIncompatible ||
           error.code == ConnectionErrorCode.authenticationFailed ||
           error.code == ConnectionErrorCode.serverVersionTooLow;
  }
  
  /// 开始自动重连
  void _startReconnect() {
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    _reconnectAttempts = 0;
    _setState(ConnectionState.reconnecting);
    _logger.log('开始自动重连', tag: 'RECONNECT');
    
    _scheduleReconnect();
  }
  
  /// 调度下一次重连
  void _scheduleReconnect() {
    if (!_isReconnecting) return;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, _attemptReconnect);
  }
  
  /// 尝试重连
  Future<void> _attemptReconnect() async {
    if (!_isReconnecting) return;
    
    _reconnectAttempts++;
    _logger.log('尝试重连 (第 $_reconnectAttempts 次，最多 $_maxReconnectAttempts 次)', tag: 'RECONNECT');
    
    // 广播重连尝试事件（保持 reconnecting 状态，只更新尝试次数）
    _stateController.add(ConnectionStateChange(
      oldState: ConnectionState.reconnecting,
      newState: ConnectionState.reconnecting,
      data: {'attempt': _reconnectAttempts, 'maxAttempts': _maxReconnectAttempts},
    ));
    
    try {
      // 尝试连接（内部连接，不改变外部状态）
      final error = await _connectInternal();
      
      if (error == null) {
        // 连接成功
        _logger.log('重连成功', tag: 'RECONNECT');
        _isReconnecting = false;
        _reconnectAttempts = 0;
        
        // 如果之前注册过设备，自动重新注册
        if (_lastDeviceModel != null && _state == ConnectionState.connected) {
          _logger.log('自动重新注册设备: $_lastDeviceModel', tag: 'RECONNECT');
          final registerError = await registerDevice(_lastDeviceModel!);
          if (registerError != null) {
            _logger.log('重新注册设备失败: ${registerError.message}', tag: 'RECONNECT');
          }
        }
        return;
      }
      
      // 连接失败
      _logger.log('重连失败: ${error.message}', tag: 'RECONNECT');
      
      // 检查是否是认证失败，如果是则停止重连
      if (_isAuthFailure(error)) {
        _logger.log('认证失败，停止重连', tag: 'RECONNECT');
        _isReconnecting = false;
        _reconnectAttempts = 0;
        _setState(ConnectionState.disconnected);
        return;
      }
      
      // 检查是否达到最大重连次数
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        _logger.log('达到最大重连次数，停止重连', tag: 'RECONNECT');
        _isReconnecting = false;
        _reconnectAttempts = 0;
        _setState(ConnectionState.disconnected);
        return;
      }
      
      // 继续重连（保持 reconnecting 状态）
      _scheduleReconnect();
      
    } catch (e) {
      _logger.logError('重连异常', error: e);
      
      // 检查是否达到最大重连次数
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        _logger.log('达到最大重连次数，停止重连', tag: 'RECONNECT');
        _isReconnecting = false;
        _reconnectAttempts = 0;
        _setState(ConnectionState.disconnected);
        return;
      }
      
      // 继续重连
      _scheduleReconnect();
    }
  }
  
  /// 内部连接方法（用于重连，不改变外部状态）
  Future<ConnectionError?> _connectInternal() async {
    _lastError = null;

    try {
      // 1. 认证预检查
      final precheckError = await _authenticatePrecheck();
      if (precheckError != null) {
        _setError(precheckError);
        return precheckError;
      }

      // 2. 建立WebSocket连接
      final wsError = await _connectWebSocket();
      if (wsError != null) {
        _setError(wsError);
        return wsError;
      }

      // 连接成功，状态已在 _handleConnectedNotification 中更新
      return null;
    } catch (e, stackTrace) {
      _logger.logError('连接失败', error: e, stackTrace: stackTrace);
      final error = ConnectionError.fromException(e);
      _setError(error);
      return error;
    }
  }

  /// 启动心跳
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
    _logger.log('心跳已启动', tag: 'HEARTBEAT');
  }

  /// 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 发送心跳
  Future<void> _sendHeartbeat() async {
    if (!isConnected) return;

    try {
      final result = await sendRequest('ping', {}).timeout(
        _heartbeatTimeout,
        onTimeout: () {
          _logger.log('心跳超时', tag: 'HEARTBEAT');
          return {'success': false, 'error': '心跳超时'};
        },
      );

      if (result['success'] != true) {
        _logger.log('心跳失败: ${result['error']}', tag: 'HEARTBEAT');
      }
    } catch (e) {
      _logger.log('心跳异常: $e', tag: 'HEARTBEAT');
    }
  }

  /// 完成所有待处理请求为失败
  void _failAllPendingRequests(String reason) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete({
          'success': false,
          'error': reason,
        });
      }
    }
    _pendingRequests.clear();
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
