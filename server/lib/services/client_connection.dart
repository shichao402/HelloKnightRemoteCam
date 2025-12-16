import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 客户端连接状态
enum ClientConnectionState {
  /// 已连接（WebSocket已建立）
  connected,

  /// 已注册（设备已注册，独占连接）
  registered,

  /// 已断开
  disconnected,
}

/// 客户端连接信息
/// 
/// 统一管理一个客户端的所有连接相关信息：
/// - WebSocket通道
/// - IP地址
/// - 设备信息
/// - 心跳状态
/// - 预览流控制器
class ClientConnection {
  /// WebSocket通道
  final WebSocketChannel channel;

  /// 客户端IP地址
  final String ipAddress;

  /// 客户端版本
  final String? clientVersion;

  /// 连接时间
  final DateTime connectedAt;

  /// 最后活跃时间
  DateTime lastActivity;

  /// 连接状态
  ClientConnectionState _state = ClientConnectionState.connected;
  ClientConnectionState get state => _state;

  /// 设备型号（注册后设置）
  String? deviceModel;

  /// 预览流控制器（如果有）
  StreamController<List<int>>? previewStreamController;

  /// 心跳历史记录（用于计算健康度）
  final List<DateTime> _heartbeatHistory = [];
  static const int _heartbeatHistoryWindowSeconds = 10;

  ClientConnection({
    required this.channel,
    required this.ipAddress,
    this.clientVersion,
  })  : connectedAt = DateTime.now(),
        lastActivity = DateTime.now();

  /// 是否已注册
  bool get isRegistered => _state == ClientConnectionState.registered;

  /// 是否已断开
  bool get isDisconnected => _state == ClientConnectionState.disconnected;

  /// 记录心跳
  void recordHeartbeat() {
    final now = DateTime.now();
    lastActivity = now;
    _heartbeatHistory.add(now);

    // 只保留最近10秒的心跳记录
    final cutoffTime =
        now.subtract(Duration(seconds: _heartbeatHistoryWindowSeconds));
    _heartbeatHistory.removeWhere((timestamp) => timestamp.isBefore(cutoffTime));
  }

  /// 计算心跳健康度（百分比）
  double getHeartbeatHealth() {
    if (_heartbeatHistory.isEmpty) {
      return 0.0;
    }

    final now = DateTime.now();
    final cutoffTime =
        now.subtract(Duration(seconds: _heartbeatHistoryWindowSeconds));
    final recentHeartbeats =
        _heartbeatHistory.where((timestamp) => timestamp.isAfter(cutoffTime)).length;

    // 理想情况下，10秒内应该有10次心跳（1秒一次）
    final expectedHeartbeats = _heartbeatHistoryWindowSeconds;
    final health =
        (recentHeartbeats / expectedHeartbeats * 100).clamp(0.0, 100.0);

    return health;
  }

  /// 检查是否超时（心跳超时）
  bool isHeartbeatTimeout({int timeoutSeconds = 10}) {
    final now = DateTime.now();
    return now.difference(lastActivity).inSeconds > timeoutSeconds;
  }

  /// 注册设备
  void register(String model) {
    deviceModel = model;
    _state = ClientConnectionState.registered;
  }

  /// 标记为断开
  void markDisconnected() {
    _state = ClientConnectionState.disconnected;
  }

  /// 关闭连接
  Future<void> close() async {
    markDisconnected();

    // 关闭预览流
    if (previewStreamController != null && !previewStreamController!.isClosed) {
      try {
        await previewStreamController!.close();
      } catch (e) {
        // 忽略关闭错误
      }
      previewStreamController = null;
    }

    // 关闭WebSocket
    try {
      await channel.sink.close();
    } catch (e) {
      // 忽略关闭错误
    }
  }

  @override
  String toString() {
    return 'ClientConnection(ip: $ipAddress, state: $_state, device: $deviceModel, version: $clientVersion)';
  }
}

/// 客户端连接管理器
/// 
/// 职责：
/// - 管理所有客户端连接
/// - 维护独占连接状态
/// - 处理心跳超时
/// - 清理断开的连接
class ClientConnectionManager {
  /// 当前独占连接（只允许一个客户端控制）
  ClientConnection? _exclusiveConnection;
  ClientConnection? get exclusiveConnection => _exclusiveConnection;

  /// 所有活跃的WebSocket连接
  final List<ClientConnection> _connections = [];
  List<ClientConnection> get connections => List.unmodifiable(_connections);

  /// 连接数量
  int get connectionCount => _connections.length;

  /// 是否有独占连接
  bool get hasExclusiveConnection => _exclusiveConnection != null;

  /// 独占连接的设备型号
  String? get exclusiveDeviceModel => _exclusiveConnection?.deviceModel;

  /// 添加新连接
  /// 
  /// 返回：true表示成功，false表示被拒绝（已有独占连接）
  bool addConnection(ClientConnection connection) {
    // 检查是否已有独占连接
    if (_exclusiveConnection != null && _exclusiveConnection != connection) {
      return false;
    }

    _connections.add(connection);

    // 如果是第一个连接，设置为独占连接
    if (_exclusiveConnection == null) {
      _exclusiveConnection = connection;
    }

    return true;
  }

  /// 移除连接
  /// 
  /// 返回：true表示移除的是独占连接
  bool removeConnection(ClientConnection connection) {
    _connections.remove(connection);

    // 如果移除的是独占连接，清除独占状态
    if (_exclusiveConnection == connection) {
      _exclusiveConnection = null;
      return true;
    }
    return false;
  }

  /// 根据WebSocket通道移除连接
  /// 
  /// 返回：true表示移除的是独占连接
  bool removeByChannel(WebSocketChannel channel) {
    final connection = findByChannel(channel);
    if (connection != null) {
      return removeConnection(connection);
    }
    return false;
  }

  /// 根据WebSocket通道查找连接
  ClientConnection? findByChannel(WebSocketChannel channel) {
    try {
      return _connections.firstWhere((c) => c.channel == channel);
    } catch (e) {
      return null;
    }
  }

  /// 根据IP地址查找连接
  ClientConnection? findByIp(String ipAddress) {
    try {
      return _connections.firstWhere((c) => c.ipAddress == ipAddress);
    } catch (e) {
      return null;
    }
  }

  /// 注册设备（设置独占连接的设备型号）
  /// 
  /// 返回：true表示成功，false表示失败（不是独占连接）
  bool registerDevice(ClientConnection connection, String deviceModel) {
    if (_exclusiveConnection != connection) {
      return false;
    }

    connection.register(deviceModel);
    return true;
  }

  /// 设置连接的设备型号
  void setDeviceModel(ClientConnection connection, String deviceModel) {
    connection.deviceModel = deviceModel;
    if (_exclusiveConnection == connection && connection.state != ClientConnectionState.registered) {
      connection.register(deviceModel);
    }
  }

  /// 记录心跳
  void recordHeartbeat(ClientConnection connection) {
    connection.recordHeartbeat();
  }

  /// 清理超时连接
  /// 
  /// 返回：被清理的连接列表
  List<ClientConnection> cleanupTimeoutConnections({int timeoutSeconds = 10}) {
    final timeoutConnections = <ClientConnection>[];

    _connections.removeWhere((connection) {
      final isTimeout = connection.isHeartbeatTimeout(timeoutSeconds: timeoutSeconds);
      if (isTimeout) {
        timeoutConnections.add(connection);
        connection.markDisconnected();

        // 如果是独占连接，清除独占状态
        if (_exclusiveConnection == connection) {
          _exclusiveConnection = null;
        }
      }
      return isTimeout;
    });

    return timeoutConnections;
  }

  /// 检查独占连接状态一致性
  /// 
  /// 如果没有活跃连接但独占状态还在，清理独占状态
  void checkExclusiveConsistency() {
    if (_connections.isEmpty && _exclusiveConnection != null) {
      _exclusiveConnection = null;
    }
  }

  /// 关闭所有连接
  Future<void> closeAll() async {
    final connectionsToClose = List<ClientConnection>.from(_connections);
    _connections.clear();
    _exclusiveConnection = null;

    for (final connection in connectionsToClose) {
      await connection.close();
    }
  }

  /// 获取所有已注册的设备IP列表
  List<String> getRegisteredDeviceIps() {
    return _connections
        .where((c) => c.isRegistered)
        .map((c) => c.ipAddress)
        .toList();
  }
}
