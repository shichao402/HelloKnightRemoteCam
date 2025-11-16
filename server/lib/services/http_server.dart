import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'camera_service.dart';
import 'settings_service.dart';
import 'device_info_service.dart';
import 'logger_service.dart';
import 'operation_log_service.dart';
import 'foreground_service.dart';
import 'media_scanner_service.dart';
import 'orientation_service.dart';
import 'version_compatibility_service.dart';
import 'auth_service.dart';
import '../models/camera_settings.dart';
import '../models/camera_capabilities.dart';
import '../models/camera_status.dart';
import '../models/file_info.dart';
import '../screens/server_settings_screen.dart';
import '../main.dart' as main_app;

class ConnectedDevice {
  final String ipAddress;
  final DateTime connectedAt;
  DateTime lastActivity;
  // 心跳历史记录：记录最近10秒内的心跳时间戳（用于计算健康度）
  final List<DateTime> _heartbeatHistory = [];
  static const int _heartbeatHistoryWindowSeconds = 10; // 记录最近10秒的心跳

  ConnectedDevice({
    required this.ipAddress,
    required this.connectedAt,
    required this.lastActivity,
  });

  // 记录一次心跳
  void recordHeartbeat() {
    final now = DateTime.now();
    lastActivity = now;
    _heartbeatHistory.add(now);
    
    // 只保留最近10秒的心跳记录
    final cutoffTime = now.subtract(Duration(seconds: _heartbeatHistoryWindowSeconds));
    _heartbeatHistory.removeWhere((timestamp) => timestamp.isBefore(cutoffTime));
  }

  // 计算心跳健康度（百分比）：最近10秒内应该收到10次心跳（1秒一次）
  double getHeartbeatHealth() {
    if (_heartbeatHistory.isEmpty) {
      return 0.0;
    }
    
    final now = DateTime.now();
    final cutoffTime = now.subtract(Duration(seconds: _heartbeatHistoryWindowSeconds));
    final recentHeartbeats = _heartbeatHistory.where((timestamp) => 
      timestamp.isAfter(cutoffTime)
    ).length;
    
    // 理想情况下，10秒内应该有10次心跳（1秒一次）
    final expectedHeartbeats = _heartbeatHistoryWindowSeconds;
    final health = (recentHeartbeats / expectedHeartbeats * 100).clamp(0.0, 100.0);
    
    return health;
  }
}

class HttpServerService {
  final CameraService cameraService;
  final SettingsService settingsService;
  final LoggerService logger = LoggerService();
  final OperationLogService operationLog = OperationLogService();
  final ForegroundService _foregroundService = ForegroundService();
  final DeviceInfoService _deviceInfoService = DeviceInfoService();
  final OrientationService _orientationService = OrientationService();
  final VersionCompatibilityService _versionCompatibilityService = VersionCompatibilityService();
  final AuthService _authService = AuthService();
  
  HttpServer? _server;
  String? _ipAddress;
  int _port = 8080;
  final Map<String, ConnectedDevice> _connectedDevices = {};
  
  // 预览流连接跟踪：记录每个客户端IP对应的StreamController
  final Map<String, StreamController<List<int>>> _previewStreamControllers = {};
  
  // 单一预览帧广播循环
  Timer? _previewBroadcastTimer;
  int _globalFrameCount = 0;
  
  // WebSocket连接：用于双向通讯通知客户端有新文件
  final List<WebSocketChannel> _webSocketChannels = [];
  
  // WebSocket channel到IP地址的映射
  final Map<WebSocketChannel, String> _webSocketChannelToIp = {};
  
  // 独占连接：当前连接的客户端标识（设备型号）
  String? _exclusiveClientDeviceModel;
  WebSocketChannel? _exclusiveWebSocketChannel;
  
  // 自动停止相关
  Timer? _autoStopTimer;
  DateTime? _noConnectionStartTime;
  bool _autoStopEnabled = false;
  int _autoStopSeconds = 20; // 改为秒为单位，默认20秒
  VoidCallback? _onAutoStop;

  HttpServerService({
    required this.cameraService,
    required this.settingsService,
  });
  
  // 设置自动停止回调
  void setAutoStopCallback(VoidCallback? callback) {
    _onAutoStop = callback;
  }
  
  // 更新自动停止设置
  Future<void> updateAutoStopSettings() async {
    final enabled = await ServerSettings.getAutoStopEnabled();
    final seconds = await ServerSettings.getAutoStopSeconds();
    
    logger.log('更新自动停止设置: 启用=$enabled, 秒数=$seconds', tag: 'AUTO_STOP');
    
    _autoStopEnabled = enabled;
    _autoStopSeconds = seconds;
    
    // 如果启用了自动停止，启动定时器（持续监控连接状态）
    if (_autoStopEnabled && isRunning) {
      logger.log('自动停止已启用，启动监控定时器', tag: 'AUTO_STOP');
      _startAutoStopTimer();
    } else {
      logger.log('自动停止未启用或服务器未运行，取消定时器 (enabled=$enabled, isRunning=$isRunning)', tag: 'AUTO_STOP');
      _cancelAutoStopTimer();
    }
  }

  // 更新连接设备信息（仅在ping心跳时调用）
  void _updateConnectedDevice(String ipAddress) {
    // 忽略unknown和无效IP
    if (ipAddress == 'unknown' || ipAddress.isEmpty) {
      return;
    }
    
    final now = DateTime.now();
    final wasNew = !_connectedDevices.containsKey(ipAddress);
    
    if (_connectedDevices.containsKey(ipAddress)) {
      _connectedDevices[ipAddress]!.recordHeartbeat();
    } else {
      final device = ConnectedDevice(
        ipAddress: ipAddress,
        connectedAt: now,
        lastActivity: now,
      );
      device.recordHeartbeat(); // 记录首次心跳
      _connectedDevices[ipAddress] = device;
      logger.log('新设备连接: $ipAddress', tag: 'CONNECTION');
    }
    
    // 清理10秒未活动的设备（基于ping心跳：客户端每1秒ping一次，10秒是10个周期）
    final heartbeatTimeoutSeconds = 10; // 心跳超时10秒
    final removed = <String>[];
    _connectedDevices.removeWhere((ip, device) {
      final inactive = now.difference(device.lastActivity).inSeconds > heartbeatTimeoutSeconds;
      if (inactive) {
        removed.add(ip);
        logger.log('设备断开连接: $ip (ping心跳超时${heartbeatTimeoutSeconds}秒)', tag: 'CONNECTION');
      }
      return inactive;
    });
    
    // 如果有变化，通知监听者（如果实现了）
    if (wasNew || removed.isNotEmpty) {
      _notifyListeners();
    }
  }
  
  // 检查自动停止状态（简化版本：只清理过期连接，不管理定时器）
  void _checkAutoStop() {
    if (!_autoStopEnabled || !isRunning) {
      return;
    }
    
    // 清理过期的连接（10秒未活动视为断开，基于ping心跳）
    final heartbeatTimeoutSeconds = 10; // 心跳超时10秒
    final now = DateTime.now();
    _connectedDevices.removeWhere((ip, device) {
      final inactive = now.difference(device.lastActivity).inSeconds > heartbeatTimeoutSeconds;
      if (inactive) {
        logger.log('设备断开连接: $ip (ping心跳超时${heartbeatTimeoutSeconds}秒)', tag: 'CONNECTION');
      }
      return inactive;
    });
  }
  
  // 启动自动停止定时器（简化版本：持续运行，定期检查）
  void _startAutoStopTimer() {
    // 如果定时器已经在运行，不重复启动
    if (_autoStopTimer != null) {
      return;
    }
    
    // 如果设置为0秒，表示无限时间，不启动定时器
    if (_autoStopSeconds == 0) {
      logger.log('自动停止设置为无限时间，不会自动停止服务器', tag: 'AUTO_STOP');
      return;
    }
    
    logger.log('启动自动停止定时器：秒数=$_autoStopSeconds', tag: 'AUTO_STOP');
    
    // 每1秒检查一次（应用在后台时也能正常工作，因为有前台服务）
    _autoStopTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_autoStopEnabled || !isRunning) {
        timer.cancel();
        _autoStopTimer = null;
        _noConnectionStartTime = null;
        return;
      }
      
      final now = DateTime.now();
      
      // 清理过期连接（10秒未活动视为断开，基于ping心跳）
      final heartbeatTimeoutSeconds = 10; // 心跳超时10秒
      _connectedDevices.removeWhere((ip, device) {
        final inactiveSeconds = now.difference(device.lastActivity).inSeconds;
        final inactive = inactiveSeconds > heartbeatTimeoutSeconds;
        if (inactive) {
          logger.log('设备断开连接: $ip (ping心跳超时${heartbeatTimeoutSeconds}秒，实际不活跃${inactiveSeconds}秒)', tag: 'CONNECTION');
        }
        return inactive;
      });
      
      // 检查连接状态
      if (_connectedDevices.isEmpty) {
        // 没有连接，开始或继续计时
        if (_noConnectionStartTime == null) {
          _noConnectionStartTime = now;
          logger.log('开始自动停止计时，无连接时间: ${_noConnectionStartTime}', tag: 'AUTO_STOP');
        } else {
          final elapsed = now.difference(_noConnectionStartTime!);
          final elapsedSeconds = elapsed.inSeconds;
          
          // 每5秒记录一次进度（避免日志过多）
          if (elapsedSeconds % 5 == 0) {
            logger.log('自动停止计时中：已无连接 ${elapsedSeconds}秒 / ${_autoStopSeconds}秒', tag: 'AUTO_STOP');
          }
          
          // 如果达到设定的秒数，执行自动停止
          if (elapsedSeconds >= _autoStopSeconds) {
            timer.cancel();
            _autoStopTimer = null;
            logger.log('自动停止服务器：无客户端连接已超过${_autoStopSeconds}秒', tag: 'AUTO_STOP');
            if (_onAutoStop != null) {
              logger.log('调用自动停止回调', tag: 'AUTO_STOP');
              _onAutoStop!();
            } else {
              logger.logError('自动停止回调为null，无法停止服务器', error: Exception('回调未设置'));
            }
          }
        }
      } else {
        // 有连接，重置计时
        if (_noConnectionStartTime != null) {
          logger.log('检测到活跃连接，取消自动停止计时', tag: 'AUTO_STOP');
          _noConnectionStartTime = null;
        }
      }
    });
  }
  
  // 取消自动停止定时器
  void _cancelAutoStopTimer() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
  }
  
  // 通知监听者（用于UI更新）
  void _notifyListeners() {
    // 这个方法可以被扩展为使用Stream或ValueNotifier
    // 目前UI通过定时刷新来更新
  }
  
  // 启动单一预览帧广播循环
  void _startPreviewBroadcast() {
    if (_previewBroadcastTimer != null) {
      return; // 已经启动
    }
    
    logger.log('启动单一预览帧广播循环', tag: 'PREVIEW');
    
    // 根据预览帧率计算延迟时间（默认10fps）
    final previewFps = cameraService.settings.previewFps;
    final delayMs = 1000 ~/ previewFps;
    
    _previewBroadcastTimer = Timer.periodic(Duration(milliseconds: delayMs), (timer) async {
      // 如果没有活跃的预览流连接，跳过
      if (_previewStreamControllers.isEmpty) {
        return;
      }
      
      // 检查服务器是否还在运行
      if (!isRunning) {
        timer.cancel();
        _previewBroadcastTimer = null;
        return;
      }
      
      // 检查相机是否已初始化
      if (!cameraService.isInitialized) {
        return;
      }
      
      try {
        // 获取最新的预览帧
        final frameData = await cameraService.capturePreviewFrame();
        if (frameData == null) {
          return;
        }
        
        _globalFrameCount++;
        
        // 每100帧记录一次日志
        if (_globalFrameCount % 100 == 0) {
          logger.log('广播预览帧 #$_globalFrameCount 给 ${_previewStreamControllers.length} 个客户端，大小: ${frameData.length} 字节', tag: 'PREVIEW');
        }
        
        // 准备MJPEG格式的数据
        const boundary = 'frame';
        final boundaryHeader = utf8.encode('--$boundary\r\n');
        final contentType = utf8.encode('Content-Type: image/jpeg\r\n');
        final contentLength = utf8.encode('Content-Length: ${frameData.length}\r\n\r\n');
        final boundaryFooter = utf8.encode('\r\n--$boundary\r\n');
        
        // 广播给所有活跃的客户端连接
        final clientsToRemove = <String>[];
        for (final entry in _previewStreamControllers.entries) {
          final clientIp = entry.key;
          final controller = entry.value;
          
          // 检查控制器是否已关闭
          if (controller.isClosed) {
            clientsToRemove.add(clientIp);
            continue;
          }
          
          try {
            // 发送预览帧数据
            controller.add(boundaryHeader);
            controller.add(contentType);
            controller.add(contentLength);
            controller.add(frameData);
            controller.add(boundaryFooter);
          } catch (e) {
            // 发送失败，可能是连接已断开
            logger.log('向客户端 $clientIp 发送预览帧失败: $e', tag: 'PREVIEW');
            clientsToRemove.add(clientIp);
          }
        }
        
        // 清理已断开的客户端连接
        for (final clientIp in clientsToRemove) {
          logger.log('清理断开的预览流连接: $clientIp', tag: 'PREVIEW');
          final controller = _previewStreamControllers.remove(clientIp);
          if (controller != null && !controller.isClosed) {
            try {
              await controller.close();
            } catch (e) {
              logger.log('关闭预览流控制器时出错: $e', tag: 'PREVIEW');
            }
          }
        }
      } catch (e, stackTrace) {
        logger.logError('预览帧广播错误', error: e, stackTrace: stackTrace);
      }
    });
  }
  
  // 停止预览帧广播循环
  void _stopPreviewBroadcast() {
    _previewBroadcastTimer?.cancel();
    _previewBroadcastTimer = null;
    _globalFrameCount = 0;
    logger.log('已停止预览帧广播循环', tag: 'PREVIEW');
  }

  // 启动服务器
  Future<String> start(int port) async {
    // 设置预览帧处理回调：只有在有活跃预览流连接时才处理预览帧
    cameraService.setHasActiveClientsCallback(() {
      return _previewStreamControllers.isNotEmpty;
    });
    
    // 启动单一预览帧广播循环
    _startPreviewBroadcast();
    
    // 启动方向监听并设置回调
    _orientationService.onOrientationChanged = (orientation) {
      _broadcastOrientationChange(orientation);
    };
    _orientationService.startListening();
    
    _port = port;
    final app = Router();

    // CORS 中间件（允许跨域）
    Middleware corsMiddleware() {
      return createMiddleware(
        responseHandler: (Response response) {
          return response.change(headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Origin, Content-Type',
          });
        },
      );
    }

    // 统一认证中间件（版本检查 + 用户认证）
    Middleware authMiddleware() {
      return (Handler handler) {
        return (Request request) async {
          // WebSocket、预览流和认证预检查端点已在路由处理中进行认证，跳过中间件
          if (request.url.path == '/ws' || 
              request.url.path == '/preview/stream' ||
              request.url.path == '/auth/precheck') {
            return handler(request);
          }

          // 执行统一认证（版本检查 + 用户认证）
          final authResult = await _authService.authenticate(request);
          
          if (!authResult.success) {
            logger.log('认证失败: ${authResult.reason} (路径: ${request.url.path})', tag: 'AUTH');
            return await _authService.createAuthFailureResponse(authResult);
          }

          // 将认证上下文存储到请求上下文中，供后续处理使用
          final context = authResult.context!;
          final updatedRequest = request.change(
            context: {
              ...request.context,
              'auth.context': context,
            },
          );

          return handler(updatedRequest);
        };
      };
    }

    // 请求日志中间件
    Middleware requestLoggingMiddleware() {
      return (Handler handler) {
        return (Request request) async {
          // 获取客户端IP地址（多种方式尝试）
          String clientIp = 'unknown';
          
          // 方法1: 从请求头获取（如果有代理）
          if (request.headers.containsKey('x-forwarded-for')) {
            final forwarded = request.headers['x-forwarded-for']!;
            // x-forwarded-for可能包含多个IP，取第一个
            clientIp = forwarded.split(',').first.trim();
          }
          
          // 方法2: 从连接信息获取（直接连接）
          if (clientIp == 'unknown') {
            final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
            if (connectionInfo != null) {
              clientIp = connectionInfo.remoteAddress.address;
            }
          }
          
          // 方法3: 从请求的IP头获取
          if (clientIp == 'unknown' && request.headers.containsKey('x-real-ip')) {
            clientIp = request.headers['x-real-ip']!;
          }
          
          // 记录请求
          logger.logHttpRequest(request.method, request.url.path);
          
          // OPTIONS 请求直接通过（CORS 预检）
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
              'Access-Control-Allow-Headers': 'Origin, Content-Type',
            });
          }

          // 注意：不再在中间件中更新连接状态，只在ping心跳时更新
          // 这样可以确保只有活跃的ping心跳才会保持连接状态
          
          final response = await handler(request);
          logger.logHttpResponse(response.statusCode, request.url.path);
          return response;
        };
      };
    }

    // 注意：HTTP ping端点已移除，所有交互都通过WebSocket
    // 如果需要兼容旧客户端，可以保留此端点，但新客户端应使用WebSocket ping

    // API端点
    final apiRouter = Router();

    // 认证预检查端点：在连接WebSocket之前进行认证检查（版本检查、用户认证等）
    apiRouter.get('/auth/precheck', (Request request) async {
      logger.log('收到认证预检查请求', tag: 'AUTH');
      
      // 执行统一认证（版本检查 + 用户认证）
      final authResult = await _authService.authenticate(request);
      
      if (!authResult.success) {
        logger.log('认证预检查失败: ${authResult.reason}', tag: 'AUTH');
        return await _authService.createAuthFailureResponse(authResult);
      }
      
      // 认证通过，返回成功响应（包含服务器版本等信息）
      final serverVersion = await _versionCompatibilityService.getServerVersion();
      return Response.ok(
        json.encode({
          'success': true,
          'message': '认证通过',
          'serverVersion': serverVersion,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 注意：控制类端点（capture, recording/start, recording/stop）已迁移到WebSocket
    // 不再提供HTTP端点

    // WebSocket端点：用于双向通讯（独占连接）
    // 使用统一认证服务进行认证
    apiRouter.get('/ws', (Request request) async {
      // 执行统一认证（版本检查 + 用户认证）
      final authResult = await _authService.authenticate(request);
      
      if (!authResult.success) {
        logger.log('WebSocket认证失败: ${authResult.reason}', tag: 'AUTH');
        return await _authService.createAuthFailureResponse(authResult);
      }

      // 获取认证上下文
      final context = authResult.context!;
      final clientIpForChannel = context.clientIp;
      final clientVersionForChannel = context.clientVersion;
      
      // 调用webSocketHandler，并在回调中使用捕获的IP地址和版本号
      return webSocketHandler((WebSocketChannel channel, String? protocol) async {
        
        // 检查是否已有独占客户端连接
        if (_exclusiveWebSocketChannel != null && _exclusiveWebSocketChannel != channel) {
          logger.log('拒绝新WebSocket连接：已有独占客户端连接（设备: $_exclusiveClientDeviceModel）', tag: 'WEBSOCKET');
          // 发送拒绝消息并关闭连接
          channel.sink.add(json.encode({
            'type': 'notification',
            'event': 'connection_rejected',
            'data': {
              'reason': 'exclusive_connection',
              'message': '服务器已被其他客户端独占连接',
              'currentClient': _exclusiveClientDeviceModel,
            },
          }));
          Future.delayed(const Duration(milliseconds: 100), () {
            channel.sink.close();
          });
          return;
        }
        
        _webSocketChannels.add(channel);
        
        // 存储WebSocket channel到IP地址的映射
        if (clientIpForChannel != null) {
          _webSocketChannelToIp[channel] = clientIpForChannel;
          logger.log('WebSocket连接客户端IP: $clientIpForChannel (版本: ${clientVersionForChannel ?? "未知"})', tag: 'WEBSOCKET');
        }
        
        // 如果是第一个连接，设置为独占连接
        if (_exclusiveWebSocketChannel == null) {
          _exclusiveWebSocketChannel = channel;
          logger.log('设置独占WebSocket连接，当前连接数: ${_webSocketChannels.length}', tag: 'WEBSOCKET');
        }
        
        logger.log('客户端已连接WebSocket，当前连接数: ${_webSocketChannels.length}', tag: 'WEBSOCKET');
        
        // 发送初始连接确认（包含预览尺寸和服务器版本）
        final previewSize = cameraService.getPreviewSize();
        final serverVersion = await _versionCompatibilityService.getServerVersion();
        channel.sink.add(json.encode({
          'type': 'notification',
          'event': 'connected',
          'data': {
            'status': 'connected',
            'exclusive': _exclusiveWebSocketChannel == channel,
            'previewSize': previewSize, // 包含预览尺寸
            'serverVersion': serverVersion, // 服务器版本号
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        }));
        
        // 监听客户端消息（双向通讯）
        channel.stream.listen(
          (message) {
            _handleWebSocketMessage(channel, message, clientIpForChannel);
          },
          onDone: () {
            _handleWebSocketDisconnect(channel, clientIpForChannel);
          },
          onError: (error) {
            logger.log('WebSocket错误: $error', tag: 'WEBSOCKET');
            _handleWebSocketDisconnect(channel, clientIpForChannel);
          },
          cancelOnError: true,
        );
      })(request);
    });

    // 注意：文件列表端点（GET /files）已迁移到WebSocket
    // 不再提供HTTP端点

    // 获取缩略图（支持照片和视频）
    apiRouter.get('/file/thumbnail', (Request request) async {
      try {
        final filePath = request.url.queryParameters['path'];
        final fileType = request.url.queryParameters['type'] ?? 'video'; // 默认为video以保持兼容
        if (filePath == null) {
          return Response.badRequest(
            body: json.encode({'success': false, 'error': '缺少文件路径参数'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // 获取缩略图路径
        final thumbnailPath = await MediaScannerService.getThumbnail(filePath, fileType == 'video');
        if (thumbnailPath == null) {
          return Response(
            404,
            body: json.encode({'success': false, 'error': '缩略图不存在'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final thumbnailFile = File(thumbnailPath);
        if (!await thumbnailFile.exists()) {
          return Response(
            404,
            body: json.encode({'success': false, 'error': '缩略图文件不存在'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final thumbnailSize = await thumbnailFile.length();
        final thumbnailBytes = await thumbnailFile.readAsBytes();

        return Response.ok(
          thumbnailBytes,
          headers: {
            'Content-Type': 'image/jpeg',
            'Content-Length': thumbnailSize.toString(),
          },
        );
      } catch (e, stackTrace) {
        logger.logError('获取缩略图失败', error: e, stackTrace: stackTrace);
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // HEAD请求处理：获取文件信息（文件大小等）
    apiRouter.add('HEAD', '/file/download', (Request request) async {
      try {
        final filePath = request.url.queryParameters['path'];
        if (filePath == null) {
          return Response.badRequest(
            body: json.encode({'success': false, 'error': '缺少文件路径参数'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final file = await cameraService.getFile(filePath);
        final fileSize = await file.length();
        final filename = file.path.split('/').last;
        
        logger.log('HEAD请求: 文件路径=$filePath, 文件大小=$fileSize', tag: 'HTTP');
        
        return Response.ok(
          '',
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': 'attachment; filename="$filename"',
            'Content-Length': fileSize.toString(),
            'Accept-Ranges': 'bytes',
          },
        );
      } catch (e, stackTrace) {
        logger.logError('HEAD请求处理失败', error: e, stackTrace: stackTrace);
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 下载文件（支持Range请求用于断点续传）
    apiRouter.get('/file/download', (Request request) async {
      String? clientIp;
      try {
        // 获取客户端IP
        final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        if (connectionInfo != null) {
          clientIp = connectionInfo.remoteAddress.address;
        }
        clientIp ??= request.headers['x-forwarded-for']?.split(',').first.trim() ?? 
                     request.headers['x-real-ip'] ?? 'unknown';
        
        final filePath = request.url.queryParameters['path'];
        if (filePath == null) {
          return Response.badRequest(
            body: json.encode({'success': false, 'error': '缺少文件路径参数'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final file = await cameraService.getFile(filePath);
        final fileSize = await file.length();
        final filename = file.path.split('/').last;
        
        // 检查是否为Range请求
        final rangeHeader = request.headers['range'];
        final isRangeRequest = rangeHeader != null && rangeHeader.startsWith('bytes=');
        final isFullDownload = request.method == 'GET' && !isRangeRequest;

        // Range 请求：处理断点续传（不记录操作日志）
        if (isRangeRequest) {
          final range = rangeHeader.substring(6).split('-');
          final start = int.parse(range[0]);
          final end = range.length > 1 && range[1].isNotEmpty
              ? int.parse(range[1])
              : fileSize - 1;

          final randomAccessFile = await file.open();
          await randomAccessFile.setPosition(start);
          final length = end - start + 1;
          final bytes = await randomAccessFile.read(length);
          await randomAccessFile.close();

          return Response(
            206, // Partial Content
            body: Stream.value(bytes),
            headers: {
              'Content-Type': 'application/octet-stream',
              'Content-Disposition': 'attachment; filename="$filename"',
              'Content-Length': length.toString(),
              'Content-Range': 'bytes $start-$end/$fileSize',
              'Accept-Ranges': 'bytes',
            },
          );
        }

        // 完整文件下载 - 记录开始和完成
        if (isFullDownload) {
          // 记录下载开始
          operationLog.addLog(
            type: OperationType.downloadStart,
            clientIp: clientIp,
            fileName: filename,
          );

          // 使用 Stream 发送文件，在完成后记录下载完成
          final stream = file.openRead();
          final streamController = StreamController<List<int>>();
          
          stream.listen(
            (data) {
              streamController.add(data);
            },
            onDone: () {
              // 下载完成后记录日志
              operationLog.addLog(
                type: OperationType.downloadComplete,
                clientIp: clientIp ?? 'unknown',
                fileName: filename,
              );
              streamController.close();
            },
            onError: (error) {
              streamController.addError(error);
              streamController.close();
            },
            cancelOnError: true,
          );

          return Response.ok(
            streamController.stream,
            headers: {
              'Content-Type': 'application/octet-stream',
              'Content-Disposition': 'attachment; filename="$filename"',
              'Content-Length': fileSize.toString(),
              'Accept-Ranges': 'bytes',
            },
          );
        }

        // 如果上面的条件不满足（不应该发生），使用原来的方式
        final bytes = await file.readAsBytes();
        return Response.ok(
          bytes,
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': 'attachment; filename="$filename"',
            'Content-Length': bytes.length.toString(),
            'Accept-Ranges': 'bytes',
          },
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 注意：删除文件端点（DELETE /file/delete）已迁移到WebSocket
    // 不再提供HTTP端点

    // 注意：设置相关端点（GET /settings, GET /settings/status, POST /settings/update）已迁移到WebSocket
    // 不再提供HTTP端点

    // 实时预览流（MJPEG）
    apiRouter.get('/preview/stream', (Request request) async {
      logger.log('收到预览流请求', tag: 'PREVIEW');
      
      // 执行统一认证（版本检查 + 用户认证）
      final authResult = await _authService.authenticate(request);
      
      if (!authResult.success) {
        logger.log('预览流认证失败: ${authResult.reason}', tag: 'AUTH');
        return await _authService.createAuthFailureResponse(authResult);
      }

      // 获取认证上下文
      final context = authResult.context!;
      final clientIp = context.clientIp ?? 'unknown';
      final clientVersion = context.clientVersion;
      
      logger.log('预览流客户端IP: $clientIp (版本: ${clientVersion ?? "未知"})', tag: 'PREVIEW');
      
      // 更新连接设备信息（预览流连接也视为活跃连接）
      _updateConnectedDevice(clientIp);
      
      // 如果该客户端已有预览流连接，先关闭旧的连接
      if (_previewStreamControllers.containsKey(clientIp)) {
        logger.log('检测到重复的预览流连接，关闭旧连接: $clientIp', tag: 'PREVIEW');
        try {
          final oldController = _previewStreamControllers[clientIp];
          if (oldController != null && !oldController.isClosed) {
            await oldController.close();
          }
        } catch (e) {
          logger.log('关闭旧预览流连接时出错: $e', tag: 'PREVIEW');
        }
        _previewStreamControllers.remove(clientIp);
      }
      
      // 创建新的 StreamController 并加入到广播列表
      final controller = StreamController<List<int>>();
      _previewStreamControllers[clientIp] = controller;
      
      // 发送初始边界标记
      const boundary = 'frame';
      controller.add(utf8.encode('--$boundary\r\n'));
      
      logger.log('客户端 $clientIp 已加入预览流广播，当前客户端数: ${_previewStreamControllers.length}', tag: 'PREVIEW');
      
      // 监听控制器关闭事件，清理连接
      controller.onCancel = () {
        logger.log('客户端 $clientIp 的预览流控制器已关闭', tag: 'PREVIEW');
        if (_previewStreamControllers[clientIp] == controller) {
          _previewStreamControllers.remove(clientIp);
          logger.log('已从预览流控制器映射中移除: $clientIp，剩余客户端数: ${_previewStreamControllers.length}', tag: 'PREVIEW');
        }
      };
      
      return Response.ok(
        controller.stream,
        headers: {
          'Content-Type': 'multipart/x-mixed-replace; boundary=$boundary',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      );
    });

    // 应用中间件
    // 合并公开路由和API路由
    final allRoutes = Router();
    allRoutes.mount('/', app);  // ping端点
    allRoutes.mount('/', apiRouter);  // API端点
    
    final handler = Pipeline()
        .addMiddleware(corsMiddleware())
        .addMiddleware(logRequests())
        .addMiddleware(requestLoggingMiddleware())
        .addMiddleware(authMiddleware())  // 统一认证中间件（版本检查 + 用户认证）
        .addHandler(allRoutes);

    // 获取本机IP地址
    _ipAddress = await _getLocalIpAddress();

    // 启动服务器
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
    logger.log('服务器运行在 http://$_ipAddress:$_port', tag: 'SERVER');

    // 启动前台服务（保持应用在后台运行时继续工作）
    await _foregroundService.start();
    
    // 加载自动停止设置并启动监控定时器（isRunning是getter，基于_server != null）
    logger.log('开始加载自动停止设置...', tag: 'AUTO_STOP');
    await updateAutoStopSettings();
    logger.log('自动停止设置加载完成，enabled=$_autoStopEnabled, seconds=$_autoStopSeconds', tag: 'AUTO_STOP');

    return _ipAddress ?? 'localhost';
  }

  /// 处理WebSocket消息
  Future<void> _handleWebSocketMessage(WebSocketChannel channel, dynamic message, String? clientIp) async {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      logger.log('收到WebSocket消息: $data', tag: 'WEBSOCKET');
      
      final messageType = data['type'] as String?;
      final messageId = data['id'] as String?;
      
      if (messageType == 'request') {
        // 处理请求消息
        final action = data['action'] as String?;
        final params = data['params'] as Map<String, dynamic>? ?? {};
        
        if (action == null || messageId == null) {
          _sendWebSocketResponse(channel, messageId ?? '', false, null, '缺少action或id字段');
          return;
        }
        
        try {
          Map<String, dynamic> result;
          switch (action) {
            case 'capture':
              result = await _handleCaptureRequest(params, clientIp);
              break;
            case 'startRecording':
              result = await _handleStartRecordingRequest(params, clientIp);
              break;
            case 'stopRecording':
              result = await _handleStopRecordingRequest(params, clientIp);
              break;
            case 'getFiles':
              result = await _handleGetFilesRequest(params);
              break;
            case 'deleteFile':
              result = await _handleDeleteFileRequest(params);
              break;
            case 'toggleStarred':
              result = await _handleToggleStarredRequest(params);
              break;
            case 'getSettings':
              result = await _handleGetSettingsRequest();
              break;
            case 'updateSettings':
              result = await _handleUpdateSettingsRequest(params);
              break;
            case 'getStatus':
              result = await _handleGetStatusRequest();
              break;
            case 'getCameraCapabilities':
              result = await _handleGetCameraCapabilitiesRequest(params);
              break;
            case 'getAllCameraCapabilities':
              result = await _handleGetAllCameraCapabilitiesRequest();
              break;
            case 'getDeviceInfo':
              result = await _handleGetDeviceInfoRequest();
              break;
            case 'registerDevice':
              // 注册设备（设置独占连接的设备型号）
              result = await _handleRegisterDeviceRequest(params, channel);
              break;
            case 'ping':
              // WebSocket ping（用于心跳检测）
              // 优先使用传入的clientIp，如果没有则从channel映射中获取
              final pingIp = clientIp ?? _webSocketChannelToIp[channel];
              if (pingIp != null && pingIp != 'unknown') {
                _updateConnectedDevice(pingIp);
              }
              result = {'success': true, 'message': 'pong'};
              break;
            case 'setOrientationLock':
              result = await _handleSetOrientationLockRequest(params);
              break;
            case 'setLockedRotationAngle':
              result = await _handleSetLockedRotationAngleRequest(params);
              break;
            default:
              _sendWebSocketResponse(channel, messageId, false, null, '未知的操作类型: $action');
              return;
          }
          
          _sendWebSocketResponse(channel, messageId, true, result, null);
        } catch (e, stackTrace) {
          logger.logError('处理WebSocket请求失败: $action', error: e, stackTrace: stackTrace);
          _sendWebSocketResponse(channel, messageId, false, null, e.toString());
        }
      } else {
        logger.log('未知的WebSocket消息类型: $messageType', tag: 'WEBSOCKET');
      }
    } catch (e) {
      logger.logError('解析WebSocket消息失败', error: e);
    }
  }
  
  /// 处理WebSocket连接断开
  void _handleWebSocketDisconnect(WebSocketChannel channel, String? clientIp) {
    try {
      logger.log('客户端断开WebSocket连接${clientIp != null ? ' (IP: $clientIp)' : ''}', tag: 'WEBSOCKET');
      
      // 从WebSocket连接列表中移除
      _webSocketChannels.remove(channel);
      
      // 从IP映射中移除
      _webSocketChannelToIp.remove(channel);
      
      // 如果断开的是独占连接，清除独占状态
      if (_exclusiveWebSocketChannel == channel) {
        _exclusiveWebSocketChannel = null;
        _exclusiveClientDeviceModel = null;
        logger.log('独占WebSocket连接已断开，清除独占状态', tag: 'WEBSOCKET');
      }
      
      // 如果有IP地址，从连接设备列表中移除
      if (clientIp != null && clientIp.isNotEmpty && clientIp != 'unknown') {
        if (_connectedDevices.containsKey(clientIp)) {
          _connectedDevices.remove(clientIp);
          logger.log('已从连接设备列表中移除: $clientIp', tag: 'CONNECTION');
          
          // 通知监听者连接状态变化
          _notifyListeners();
        }
      }
      
      // 清理该客户端对应的预览流连接
      if (clientIp != null && clientIp.isNotEmpty && clientIp != 'unknown') {
        final previewController = _previewStreamControllers[clientIp];
        if (previewController != null) {
          try {
            if (!previewController.isClosed) {
              previewController.close();
            }
            _previewStreamControllers.remove(clientIp);
            logger.log('已清理客户端 $clientIp 的预览流连接', tag: 'PREVIEW');
          } catch (e) {
            logger.log('清理预览流连接时出错: $e', tag: 'PREVIEW');
            _previewStreamControllers.remove(clientIp);
          }
        }
      }
      
      logger.log('WebSocket断开处理完成，当前连接数: ${_webSocketChannels.length}', tag: 'WEBSOCKET');
    } catch (e, stackTrace) {
      logger.logError('处理WebSocket断开连接失败', error: e, stackTrace: stackTrace);
    }
  }

  void _sendWebSocketResponse(WebSocketChannel channel, String messageId, bool success, Map<String, dynamic>? data, String? error) {
    try {
      channel.sink.add(json.encode({
        'id': messageId,
        'type': 'response',
        'success': success,
        'data': data,
        'error': error,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (e) {
      logger.log('发送WebSocket响应失败: $e', tag: 'WEBSOCKET');
    }
  }
  
  /// 处理拍照请求
  Future<Map<String, dynamic>> _handleCaptureRequest(Map<String, dynamic> params, String? clientIp) async {
    logger.logCamera('开始拍照（WebSocket）');
    try {
      final filePath = await cameraService.takePicture();
      logger.logCamera('拍照成功（WebSocket）', details: filePath);
      
      if (filePath == null || filePath.isEmpty) {
        logger.logError('拍照返回空路径', error: Exception('filePath为空'));
        return {'success': false, 'error': '拍照返回空路径'};
      }
      
      final fileName = filePath.split('/').last;
      operationLog.addLog(
        type: OperationType.takePicture,
        clientIp: clientIp ?? 'websocket_client',
        fileName: fileName,
      );
      
      // 广播新文件通知
      logger.log('准备广播新照片文件: $fileName', tag: 'WEBSOCKET');
      await broadcastNewFiles([fileName], 'image');
      
      return {'success': true, 'path': filePath};
    } catch (e, stackTrace) {
      logger.logError('拍照失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理开始录像请求
  Future<Map<String, dynamic>> _handleStartRecordingRequest(Map<String, dynamic> params, String? clientIp) async {
    logger.logCamera('开始录像（WebSocket）');
    final filePath = await cameraService.startRecording();
    logger.logCamera('录像开始成功（WebSocket）', details: filePath);
    
    final fileName = filePath.split('/').last;
    operationLog.addLog(
      type: OperationType.startRecording,
      clientIp: clientIp ?? 'websocket_client',
      fileName: fileName,
    );
    
    return {'success': true, 'path': filePath};
  }
  
  /// 处理停止录像请求
  Future<Map<String, dynamic>> _handleStopRecordingRequest(Map<String, dynamic> params, String? clientIp) async {
    logger.logCamera('停止录像（WebSocket）');
    try {
      final filePath = await cameraService.stopRecording();
      logger.logCamera('录像停止成功（WebSocket）', details: filePath);
      
      if (filePath == null || filePath.isEmpty) {
        logger.logError('停止录制返回空路径', error: Exception('filePath为空'));
        return {'success': false, 'error': '停止录制返回空路径'};
      }
      
      final fileName = filePath.split('/').last;
      operationLog.addLog(
        type: OperationType.stopRecording,
        clientIp: clientIp ?? 'websocket_client',
        fileName: fileName,
      );
      
      // 广播新文件通知
      logger.log('准备广播新视频文件: $fileName', tag: 'WEBSOCKET');
      await broadcastNewFiles([fileName], 'video');
      
      return {'success': true, 'path': filePath};
    } catch (e, stackTrace) {
      logger.logError('停止录制失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理获取文件列表请求
  Future<Map<String, dynamic>> _handleGetFilesRequest(Map<String, dynamic> params) async {
    final page = params['page'] as int?;
    final pageSize = params['pageSize'] as int?;
    final since = params['since'] as int?;
    
    final result = await cameraService.getFileList(
      page: page,
      pageSize: pageSize,
      since: since,
    );
    
    return {'success': true, ...result};
  }
  
  /// 处理删除文件请求
  Future<Map<String, dynamic>> _handleDeleteFileRequest(Map<String, dynamic> params) async {
    final filePath = params['path'] as String?;
    if (filePath == null) {
      return {'success': false, 'error': '缺少文件路径参数'};
    }
    
    try {
      await cameraService.deleteFile(filePath);
      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理切换星标请求
  Future<Map<String, dynamic>> _handleToggleStarredRequest(Map<String, dynamic> params) async {
    final filePath = params['path'] as String?;
    if (filePath == null) {
      return {'success': false, 'error': '缺少文件路径参数'};
    }
    
    try {
      final newStarred = await cameraService.toggleStarred(filePath);
      return {'success': true, 'isStarred': newStarred};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理获取设置请求
  Future<Map<String, dynamic>> _handleGetSettingsRequest() async {
    final settings = await settingsService.loadSettings();
    final settingsMap = <String, dynamic>{
      'videoQuality': settings.videoQuality,
      'photoQuality': settings.photoQuality,
      'enableAudio': settings.enableAudio,
      'previewFps': settings.previewFps,
      'previewQuality': settings.previewQuality,
    };
    
    // 添加扩展参数
    if (settings.photoSize != null) {
      settingsMap['photoSize'] = settings.photoSize!.toJson();
    }
    if (settings.videoSize != null) {
      settingsMap['videoSize'] = settings.videoSize!.toJson();
    }
    if (settings.previewSize != null) {
      settingsMap['previewSize'] = settings.previewSize!.toJson();
    }
    if (settings.videoFpsRange != null) {
      settingsMap['videoFpsRange'] = settings.videoFpsRange!.toJson();
    }
    
    return {
      'success': true,
      'settings': settingsMap,
    };
  }
  
  /// 处理更新设置请求
  Future<Map<String, dynamic>> _handleUpdateSettingsRequest(Map<String, dynamic> params) async {
    try {
      final videoQualityStr = params['videoQuality'] as String?;
      final photoQualityStr = params['photoQuality'] as String?;
      final enableAudio = params['enableAudio'] as bool?;
      final previewFps = params['previewFps'] as int?;
      final previewQuality = params['previewQuality'] as int?;
      
      // 处理扩展参数
      Size? photoSize;
      Size? videoSize;
      Size? previewSize;
      FpsRange? videoFpsRange;
      
      if (params['photoSize'] != null) {
        final photoSizeMap = params['photoSize'] as Map<String, dynamic>;
        photoSize = Size.fromJson(photoSizeMap);
      }
      if (params['videoSize'] != null) {
        final videoSizeMap = params['videoSize'] as Map<String, dynamic>;
        videoSize = Size.fromJson(videoSizeMap);
      }
      // 预览尺寸完全由服务端根据设备能力决定，忽略客户端传入的previewSize
      // if (params['previewSize'] != null) {
      //   final previewSizeMap = params['previewSize'] as Map<String, dynamic>;
      //   previewSize = Size.fromJson(previewSizeMap);
      // }
      if (params['videoFpsRange'] != null) {
        final fpsRangeMap = params['videoFpsRange'] as Map<String, dynamic>;
        videoFpsRange = FpsRange.fromJson(fpsRangeMap);
      }
      
      final currentSettings = await settingsService.loadSettings();
      
      // 创建新的设置对象（包含扩展参数）
      // 注意：previewSize始终为null，因为预览尺寸由服务端根据设备能力自动决定
      final newSettings = currentSettings.copyWith(
        videoQuality: videoQualityStr,
        photoQuality: photoQualityStr,
        enableAudio: enableAudio,
        previewFps: previewFps,
        previewQuality: previewQuality,
        photoSize: photoSize,
        videoSize: videoSize,
        previewSize: null, // 预览尺寸由服务端根据设备能力自动决定，不保存客户端设置
        videoFpsRange: videoFpsRange,
      );
      
      await settingsService.saveSettings(newSettings);
      
      // 如果相机已初始化，重新配置相机以立即应用新设置
      if (cameraService.isInitialized) {
        try {
          // 获取当前相机描述（从main.dart的全局变量获取）
          if (main_app.cameras.isNotEmpty) {
            // 优先使用后置相机，如果没有则使用第一个
            CameraDescription currentCamera;
            try {
              currentCamera = main_app.cameras.firstWhere(
                (camera) => camera.lensDirection == CameraLensDirection.back,
              );
            } catch (e) {
              currentCamera = main_app.cameras.first;
            }
            await cameraService.reconfigure(newSettings, currentCamera);
            logger.log('相机已重新配置，新设置已立即生效', tag: 'SETTINGS');
          } else {
            // 如果没有可用相机，只更新设置
            cameraService.updateSettings(newSettings);
            logger.log('没有可用相机，设置已保存', tag: 'SETTINGS');
          }
        } catch (e, stackTrace) {
          logger.logError('重新配置相机失败', error: e, stackTrace: stackTrace);
          // 即使重新配置失败，也更新设置
          cameraService.updateSettings(newSettings);
        }
      } else {
        // 相机未初始化，只更新设置
        cameraService.updateSettings(newSettings);
        logger.log('相机未初始化，设置已保存，将在下次初始化时应用', tag: 'SETTINGS');
      }
      
      logger.log('相机设置已更新', tag: 'SETTINGS');
      logger.log('视频质量: ${newSettings.videoQuality}, 照片质量: ${newSettings.photoQuality}, 音频: ${newSettings.enableAudio}, 预览FPS: ${newSettings.previewFps}, 预览质量: ${newSettings.previewQuality}', tag: 'SETTINGS');
      if (newSettings.videoSize != null) {
        logger.log('视频分辨率: ${newSettings.videoSize!.width}x${newSettings.videoSize!.height}', tag: 'SETTINGS');
      }
      if (newSettings.videoFpsRange != null) {
        logger.log('视频帧率范围: ${newSettings.videoFpsRange!.min}-${newSettings.videoFpsRange!.max} fps', tag: 'SETTINGS');
      }
      
      return {'success': true};
    } catch (e, stackTrace) {
      logger.logError('更新设置失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理获取状态请求
  Future<Map<String, dynamic>> _handleGetStatusRequest() async {
    final previewSize = cameraService.getPreviewSize();
    final orientationStatus = await cameraService.getOrientationStatus();
    return {
      'success': true,
      'status': {
        'isInitialized': cameraService.isInitialized,
        'isRecording': cameraService.isRecording,
        'currentStatus': cameraService.status.toString(),
        'canChangeSettings': cameraService.status.canChangeSettings,
        'isLocked': cameraService.status.isLocked,
        'previewSize': previewSize,
        'orientation': orientationStatus ?? {
          'orientationLocked': true,
          'lockedRotationAngle': 0,
          'currentDeviceOrientation': 0,
        },
      },
    };
  }
  
  /// 处理获取相机能力请求
  Future<Map<String, dynamic>> _handleGetCameraCapabilitiesRequest(Map<String, dynamic> params) async {
    try {
      final cameraId = params['cameraId'] as String?;
      if (cameraId == null) {
        return {'success': false, 'error': '缺少cameraId参数'};
      }
      
      final capabilities = await cameraService.getCameraCapabilities(cameraId);
      if (capabilities != null) {
        return {
          'success': true,
          'capabilities': capabilities.toJson(),
        };
      } else {
        return {'success': false, 'error': '无法获取相机能力信息'};
      }
    } catch (e, stackTrace) {
      logger.logError('获取相机能力信息失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理获取所有相机能力请求
  Future<Map<String, dynamic>> _handleGetAllCameraCapabilitiesRequest() async {
    try {
      final capabilities = await cameraService.getAllCameraCapabilities();
      return {
        'success': true,
        'capabilities': capabilities.map((e) => e.toJson()).toList(),
      };
    } catch (e, stackTrace) {
      logger.logError('获取所有相机能力信息失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理获取设备信息请求
  Future<Map<String, dynamic>> _handleGetDeviceInfoRequest() async {
    try {
      final deviceInfo = await _deviceInfoService.getDeviceInfo();
      if (deviceInfo != null) {
        return {
          'success': true,
          'deviceInfo': deviceInfo,
        };
      } else {
        return {'success': false, 'error': '无法获取设备信息'};
      }
    } catch (e, stackTrace) {
      logger.logError('获取设备信息失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 处理注册设备请求（设置独占连接的设备型号）
  /// 处理设置方向锁定请求
  Future<Map<String, dynamic>> _handleSetOrientationLockRequest(Map<String, dynamic> params) async {
    try {
      final locked = params['locked'] as bool? ?? true;
      logger.log('设置方向锁定: $locked', tag: 'ORIENTATION');
      
      // 调用原生相机服务设置方向锁定
      final success = await cameraService.setOrientationLock(locked);
      
      if (success) {
        return {'success': true, 'locked': locked};
      } else {
        return {'success': false, 'error': '设置方向锁定失败'};
      }
    } catch (e, stackTrace) {
      logger.logError('处理设置方向锁定请求失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 处理设置锁定旋转角度请求
  Future<Map<String, dynamic>> _handleSetLockedRotationAngleRequest(Map<String, dynamic> params) async {
    try {
      final angle = params['angle'] as int? ?? 0;
      logger.log('设置锁定旋转角度: $angle', tag: 'ORIENTATION');
      
      // 调用原生相机服务设置锁定旋转角度
      final success = await cameraService.setLockedRotationAngle(angle);
      
      if (success) {
        return {'success': true, 'angle': angle};
      } else {
        return {'success': false, 'error': '设置锁定旋转角度失败'};
      }
    } catch (e, stackTrace) {
      logger.logError('处理设置锁定旋转角度请求失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleRegisterDeviceRequest(Map<String, dynamic> params, WebSocketChannel channel) async {
    try {
      final deviceModel = params['deviceModel'] as String?;
      final clientVersion = params['clientVersion'] as String?;
      
      if (deviceModel == null || deviceModel.isEmpty) {
        return {'success': false, 'error': '缺少deviceModel参数'};
      }
      
      // 注意：版本检查已在WebSocket连接建立时完成，这里不再重复检查
      // 如果需要在registerDevice时再次验证，可以从channel的上下文中获取认证信息
      
      // 检查是否是当前独占连接的客户端
      if (_exclusiveWebSocketChannel == channel) {
        _exclusiveClientDeviceModel = deviceModel;
        logger.log('注册独占连接设备: $deviceModel (客户端版本: ${clientVersion ?? "未知"})', tag: 'WEBSOCKET');
        return {
          'success': true,
          'message': '设备注册成功',
          'exclusive': true,
        };
      } else {
        return {
          'success': false,
          'error': '当前连接不是独占连接',
        };
      }
    } catch (e, stackTrace) {
      logger.logError('注册设备失败', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// 广播新文件通知给所有连接的客户端（通过WebSocket）
  Future<void> broadcastNewFiles(List<String> fileNames, String fileType) async {
    logger.log('准备广播新文件通知: $fileType, 文件数: ${fileNames.length}, 当前WebSocket连接数: ${_webSocketChannels.length}', tag: 'WEBSOCKET');
    
    if (_webSocketChannels.isEmpty) {
      logger.log('没有WebSocket连接，跳过广播', tag: 'WEBSOCKET');
      return;
    }
    
    // 获取文件信息列表
    // 注意：由于 takePicture() 和 stopRecording() 已经 await 了 addFile()，
    // 所以文件索引应该已经完成，可以直接查询
    final List<Map<String, dynamic>> filesData = [];
    for (final fileName in fileNames) {
      try {
        // 直接从索引获取文件信息（索引已经在 takePicture/stopRecording 中完成）
        final fileInfo = await cameraService.getFileByName(fileName);
        if (fileInfo != null) {
          filesData.add(fileInfo.toJson());
          logger.log('成功从索引获取文件信息: $fileName', tag: 'WEBSOCKET');
        } else {
          logger.log('索引中未找到文件: $fileName，尝试从文件系统获取', tag: 'WEBSOCKET');
          // 如果索引中没有，尝试从文件系统获取基本信息（作为后备方案）
          try {
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              final storageRoot = externalDir.path.split('/Android')[0];
              final filePath = fileType == 'image'
                  ? path.join(storageRoot, 'Pictures', 'RemoteCam', fileName)
                  : path.join(storageRoot, 'Movies', 'RemoteCam', fileName);
              final file = File(filePath);
              if (await file.exists()) {
                final fileSize = await file.length();
                final stat = await file.stat();
                // 使用 changed 作为创建时间（如果可用），否则使用 modified
                final createdTime = stat.changed.isBefore(stat.modified) 
                    ? stat.changed 
                    : stat.modified;
                filesData.add({
                  'name': fileName,
                  'path': filePath,
                  'size': fileSize,
                  'createdTime': createdTime.millisecondsSinceEpoch,
                  'modifiedTime': stat.modified.millisecondsSinceEpoch,
                });
                logger.log('从文件系统获取文件信息: $fileName', tag: 'WEBSOCKET');
              } else {
                logger.log('文件不存在: $filePath', tag: 'WEBSOCKET');
              }
            }
          } catch (e) {
            logger.logError('从文件系统获取文件信息失败: $fileName', error: e);
          }
        }
      } catch (e) {
        logger.logError('获取文件信息失败: $fileName', error: e);
      }
    }
    
    if (filesData.isEmpty) {
      logger.log('没有有效的文件信息，跳过广播', tag: 'WEBSOCKET');
      return;
    }
    
    final message = json.encode({
      'type': 'notification',
      'event': 'new_files',
      'data': {
        'fileType': fileType, // 'image' or 'video'
        'files': filesData, // 完整的文件信息列表
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
    
    logger.log('准备发送WebSocket消息，消息长度: ${message.length} 字节', tag: 'WEBSOCKET');
    
    // 向所有连接的客户端广播
    final channelsToRemove = <WebSocketChannel>[];
    int successCount = 0;
    for (final channel in _webSocketChannels) {
      try {
        channel.sink.add(message);
        successCount++;
        logger.log('成功发送新文件通知到客户端', tag: 'WEBSOCKET');
      } catch (e) {
        logger.log('广播新文件通知失败: $e', tag: 'WEBSOCKET');
        channelsToRemove.add(channel);
      }
    }
    
    // 清理已关闭的通道
    for (final channel in channelsToRemove) {
      _webSocketChannels.remove(channel);
    }
    
    logger.log('已广播新文件通知: $fileType, 文件数: ${filesData.length}, 成功发送: $successCount/${_webSocketChannels.length}', tag: 'WEBSOCKET');
  }
  
  /// 广播设备方向变化通知给所有连接的客户端（通过WebSocket）
  void _broadcastOrientationChange(int orientation) {
    logger.log('准备广播设备方向变化: $orientation 度, 当前WebSocket连接数: ${_webSocketChannels.length}', tag: 'WEBSOCKET');
    
    if (_webSocketChannels.isEmpty) {
      logger.log('没有WebSocket连接，跳过广播', tag: 'WEBSOCKET');
      return;
    }
    
    final message = json.encode({
      'type': 'notification',
      'event': 'orientation_changed',
      'data': {
        'orientation': orientation, // 0, 90, 180, 270
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
    
    // 向所有连接的客户端广播
    final channelsToRemove = <WebSocketChannel>[];
    int successCount = 0;
    for (final channel in _webSocketChannels) {
      try {
        channel.sink.add(message);
        successCount++;
      } catch (e) {
        logger.log('广播方向变化通知失败: $e', tag: 'WEBSOCKET');
        channelsToRemove.add(channel);
      }
    }
    
    // 清理已关闭的通道
    for (final channel in channelsToRemove) {
      _webSocketChannels.remove(channel);
    }
    
    logger.log('已广播方向变化通知: $orientation 度, 成功发送: $successCount/${_webSocketChannels.length}', tag: 'WEBSOCKET');
  }

  // 停止服务器
  Future<void> stop() async {
    // 关闭所有WebSocket连接
    for (final channel in _webSocketChannels) {
      try {
        await channel.sink.close();
      } catch (e) {
        logger.log('关闭WebSocket连接失败: $e', tag: 'WEBSOCKET');
      }
    }
    _webSocketChannels.clear();
    
    // 取消自动停止定时器
    _cancelAutoStopTimer();
    _noConnectionStartTime = null;
    
    // 停止预览帧广播循环
    _stopPreviewBroadcast();
    
    // 停止方向监听
    _orientationService.stopListening();
    
    // 关闭所有预览流连接
    logger.log('关闭所有预览流连接，共 ${_previewStreamControllers.length} 个', tag: 'PREVIEW');
    for (final entry in _previewStreamControllers.entries) {
      try {
        final controller = entry.value;
        if (!controller.isClosed) {
          await controller.close();
        }
        logger.log('已关闭预览流连接: ${entry.key}', tag: 'PREVIEW');
      } catch (e) {
        logger.log('关闭预览流连接时出错 ${entry.key}: $e', tag: 'PREVIEW');
      }
    }
    _previewStreamControllers.clear();
    
    // 停止前台服务
    await _foregroundService.stop();
    
    await _server?.close(force: true);
    _server = null;
    logger.log('服务器已停止', tag: 'SERVER');
  }

  // 获取本地IP地址
  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            // 优先返回局域网地址
            if (addr.address.startsWith('192.168.') ||
                addr.address.startsWith('10.') ||
                addr.address.startsWith('172.')) {
              return addr.address;
            }
          }
        }
      }
    } catch (e) {
      logger.logError('获取IP地址失败', error: e);
    }
    return null;
  }

  String? get ipAddress => _ipAddress;
  int get port => _port;
  bool get isRunning => _server != null;
  List<ConnectedDevice> get connectedDevices => _connectedDevices.values.toList();
  int get connectedDeviceCount => _connectedDevices.length;
  
  // 获取自动停止倒计时（秒），如果没有倒计时则返回null
  int? getAutoStopCountdown() {
    if (!_autoStopEnabled || !isRunning || _connectedDevices.isNotEmpty) {
      return null; // 未启用、未运行或有连接时，无倒计时
    }
    
    if (_noConnectionStartTime == null) {
      return null; // 还未开始计时
    }
    
    final now = DateTime.now();
    final elapsed = now.difference(_noConnectionStartTime!);
    final elapsedSeconds = elapsed.inSeconds;
    final remainingSeconds = _autoStopSeconds - elapsedSeconds;
    
    if (remainingSeconds <= 0) {
      return 0; // 倒计时已到
    }
    
    return remainingSeconds;
  }
}

