import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'camera_service.dart';
import 'settings_service.dart';
import 'logger_service.dart';
import 'operation_log_service.dart';
import 'foreground_service.dart';
import 'media_scanner_service.dart';
import '../models/camera_settings.dart';
import '../models/camera_status.dart';
import '../screens/server_settings_screen.dart';

class ConnectedDevice {
  final String ipAddress;
  final DateTime connectedAt;
  DateTime lastActivity;

  ConnectedDevice({
    required this.ipAddress,
    required this.connectedAt,
    required this.lastActivity,
  });
}

class HttpServerService {
  final CameraService cameraService;
  final SettingsService settingsService;
  final LoggerService logger = LoggerService();
  final OperationLogService operationLog = OperationLogService();
  final ForegroundService _foregroundService = ForegroundService();
  
  HttpServer? _server;
  String? _ipAddress;
  int _port = 8080;
  final Map<String, ConnectedDevice> _connectedDevices = {};
  
  // 自动停止相关
  Timer? _autoStopTimer;
  DateTime? _noConnectionStartTime;
  bool _autoStopEnabled = false;
  int _autoStopMinutes = 15;
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
    final minutes = await ServerSettings.getAutoStopMinutes();
    
    print('[AUTO_STOP] 更新自动停止设置: 启用=$enabled, 分钟数=$minutes');
    logger.log('更新自动停止设置: 启用=$enabled, 分钟数=$minutes', tag: 'AUTO_STOP');
    
    _autoStopEnabled = enabled;
    _autoStopMinutes = minutes;
    
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
      _connectedDevices[ipAddress]!.lastActivity = now;
    } else {
      _connectedDevices[ipAddress] = ConnectedDevice(
        ipAddress: ipAddress,
        connectedAt: now,
        lastActivity: now,
      );
      logger.log('新设备连接: $ipAddress', tag: 'CONNECTION');
    }
    
    // 清理30秒未活动的设备（基于ping心跳：客户端每5秒ping一次，30秒是6个周期）
    final removed = <String>[];
    _connectedDevices.removeWhere((ip, device) {
      final inactive = now.difference(device.lastActivity).inSeconds > 30;
      if (inactive) {
        removed.add(ip);
        logger.log('设备断开连接: $ip (ping心跳超时30秒)', tag: 'CONNECTION');
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
    
    // 清理过期的连接（30秒未活动视为断开，基于ping心跳）
    final now = DateTime.now();
    _connectedDevices.removeWhere((ip, device) {
      final inactive = now.difference(device.lastActivity).inSeconds > 30;
      if (inactive) {
        logger.log('设备断开连接: $ip (ping心跳超时30秒)', tag: 'CONNECTION');
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
    
    // 如果设置为0分钟，表示无限时间，不启动定时器
    if (_autoStopMinutes == 0) {
      logger.log('自动停止设置为无限时间，不会自动停止服务器', tag: 'AUTO_STOP');
      return;
    }
    
    logger.log('启动自动停止定时器：分钟数=$_autoStopMinutes', tag: 'AUTO_STOP');
    
    // 每5秒检查一次（应用在后台时也能正常工作，因为有前台服务）
    _autoStopTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_autoStopEnabled || !isRunning) {
        timer.cancel();
        _autoStopTimer = null;
        _noConnectionStartTime = null;
        return;
      }
      
      final now = DateTime.now();
      
      // 清理过期连接（30秒未活动视为断开，基于ping心跳）
      _connectedDevices.removeWhere((ip, device) {
        final inactiveSeconds = now.difference(device.lastActivity).inSeconds;
        final inactive = inactiveSeconds > 30;
        if (inactive) {
          logger.log('设备断开连接: $ip (ping心跳超时30秒，实际不活跃${inactiveSeconds}秒)', tag: 'CONNECTION');
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
          final elapsedMinutes = elapsed.inMinutes;
          final elapsedSeconds = elapsed.inSeconds;
          
          // 每30秒记录一次进度（避免日志过多）
          if (elapsedSeconds % 30 == 0) {
            logger.log('自动停止计时中：已无连接 ${elapsedMinutes}分${elapsedSeconds % 60}秒 / ${_autoStopMinutes}分钟', tag: 'AUTO_STOP');
          }
          
          // 如果达到设定的分钟数，执行自动停止
          if (elapsedMinutes >= _autoStopMinutes) {
            timer.cancel();
            _autoStopTimer = null;
            logger.log('自动停止服务器：无客户端连接已超过${_autoStopMinutes}分钟', tag: 'AUTO_STOP');
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

  // 启动服务器
  Future<String> start(int port) async {
    // 设置预览帧处理回调：只有在有活跃客户端连接时才处理预览帧
    cameraService.setHasActiveClientsCallback(() {
      return _connectedDevices.isNotEmpty;
    });
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

    // 公开端点：健康检查（带日志）
    app.get('/ping', (Request request) {
      // 获取客户端IP地址（与中间件逻辑一致）
      String clientIp = 'unknown';
      
      if (request.headers.containsKey('x-forwarded-for')) {
        final forwarded = request.headers['x-forwarded-for']!;
        clientIp = forwarded.split(',').first.trim();
      }
      
      if (clientIp == 'unknown') {
        final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        if (connectionInfo != null) {
          clientIp = connectionInfo.remoteAddress.address;
        }
      }
      
      if (clientIp == 'unknown' && request.headers.containsKey('x-real-ip')) {
        clientIp = request.headers['x-real-ip']!;
      }
      
      logger.logHttpRequest('GET', '/ping');
      logger.log('收到ping心跳请求，来自: $clientIp', tag: 'CONNECTION');
      
      // 更新连接设备信息（这是判断客户端是否在线的主要依据）
      _updateConnectedDevice(clientIp);
      return Response.ok('pong');
    });

    // API端点
    final apiRouter = Router();

    // 拍照
    apiRouter.post('/capture', (Request request) async {
      String? clientIp;
      try {
        // 获取客户端IP
        final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        if (connectionInfo != null) {
          clientIp = connectionInfo.remoteAddress.address;
        }
        clientIp ??= request.headers['x-forwarded-for']?.split(',').first.trim() ?? 
                     request.headers['x-real-ip'] ?? 'unknown';
        
        logger.logCamera('开始拍照');
        final filePath = await cameraService.takePicture();
        logger.logCamera('拍照成功', details: filePath);
        
        // 记录操作日志
        final fileName = filePath.split('/').last;
        operationLog.addLog(
          type: OperationType.takePicture,
          clientIp: clientIp,
          fileName: fileName,
        );
        
        return Response.ok(
          json.encode({'success': true, 'path': filePath}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e, stackTrace) {
        logger.logError('拍照失败', error: e, stackTrace: stackTrace);
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 开始录像
    apiRouter.post('/recording/start', (Request request) async {
      String? clientIp;
      try {
        // 获取客户端IP
        final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        if (connectionInfo != null) {
          clientIp = connectionInfo.remoteAddress.address;
        }
        clientIp ??= request.headers['x-forwarded-for']?.split(',').first.trim() ?? 
                     request.headers['x-real-ip'] ?? 'unknown';
        
        logger.logCamera('开始录像');
        final filePath = await cameraService.startRecording();
        logger.logCamera('录像开始成功', details: filePath);
        
        // 记录操作日志
        final fileName = filePath.split('/').last;
        operationLog.addLog(
          type: OperationType.startRecording,
          clientIp: clientIp,
          fileName: fileName,
        );
        
        return Response.ok(
          json.encode({'success': true, 'path': filePath}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e, stackTrace) {
        logger.logError('开始录像失败', error: e, stackTrace: stackTrace);
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 停止录像
    apiRouter.post('/recording/stop', (Request request) async {
      String? clientIp;
      try {
        // 获取客户端IP
        final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        if (connectionInfo != null) {
          clientIp = connectionInfo.remoteAddress.address;
        }
        clientIp ??= request.headers['x-forwarded-for']?.split(',').first.trim() ?? 
                     request.headers['x-real-ip'] ?? 'unknown';
        
        logger.logCamera('停止录像');
        final filePath = await cameraService.stopRecording();
        logger.logCamera('录像停止成功', details: filePath);
        
        // 记录操作日志
        final fileName = filePath.split('/').last;
        operationLog.addLog(
          type: OperationType.stopRecording,
          clientIp: clientIp,
          fileName: fileName,
        );
        
        return Response.ok(
          json.encode({'success': true, 'path': filePath}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e, stackTrace) {
        logger.logError('停止录像失败', error: e, stackTrace: stackTrace);
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 获取文件列表
    apiRouter.get('/files', (Request request) async {
      try {
        final files = await cameraService.getFileList();
        return Response.ok(
          json.encode({
            'success': true,
            'pictures': files['pictures']!.map((f) => f.toJson()).toList(),
            'videos': files['videos']!.map((f) => f.toJson()).toList(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

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
        
        // HEAD 请求：只返回 headers，不返回 body（不记录操作日志）
        if (request.method == 'HEAD') {
          return Response.ok(
            '',
            headers: {
              'Content-Type': 'application/octet-stream',
              'Content-Disposition': 'attachment; filename="$filename"',
              'Content-Length': fileSize.toString(),
              'Accept-Ranges': 'bytes',
            },
          );
        }

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

    // 删除文件
    apiRouter.delete('/file/delete', (Request request) async {
      try {
        final filePath = request.url.queryParameters['path'];
        if (filePath == null) {
          return Response.badRequest(
            body: json.encode({'success': false, 'error': '缺少文件路径参数'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        await cameraService.deleteFile(filePath);
        return Response.ok(
          json.encode({'success': true}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 获取设置状态
    apiRouter.get('/settings/status', (Request request) async {
      return Response.ok(
        json.encode({
          'success': true,
          'locked': cameraService.status.isLocked,
          'canChangeSettings': cameraService.status.canChangeSettings,
          'currentStatus': cameraService.status.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 更新设置
    apiRouter.post('/settings/update', (Request request) async {
      try {
        final bodyString = await request.readAsString();
        final body = json.decode(bodyString) as Map<String, dynamic>;
        final newSettings = CameraSettings.fromJson(body);

        // 检查是否可以更改设置
        if (!cameraService.status.canChangeSettings) {
          return Response(
            409, // Conflict
            body: json.encode({
              'success': false,
              'error': '当前状态不允许更改设置: ${cameraService.status.displayName}'
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // 需要重新初始化相机（这需要camera实例，实际实现中需要传入）
        await settingsService.saveSettings(newSettings);
        cameraService.settings = newSettings;

        return Response.ok(
          json.encode({'success': true}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: json.encode({'success': false, 'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // 获取当前设置
    apiRouter.get('/settings', (Request request) async {
      return Response.ok(
        json.encode({
          'success': true,
          'settings': cameraService.settings.toJson(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // 实时预览流（MJPEG）
    apiRouter.get('/preview/stream', (Request request) async {
      logger.log('收到预览流请求', tag: 'PREVIEW');
      
      // 获取客户端IP地址（与中间件逻辑一致）
      String clientIp = 'unknown';
      if (request.headers.containsKey('x-forwarded-for')) {
        final forwarded = request.headers['x-forwarded-for']!;
        clientIp = forwarded.split(',').first.trim();
      }
      if (clientIp == 'unknown') {
        final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        if (connectionInfo != null) {
          clientIp = connectionInfo.remoteAddress.address;
        }
      }
      if (clientIp == 'unknown' && request.headers.containsKey('x-real-ip')) {
        clientIp = request.headers['x-real-ip']!;
      }
      
      print('[PREVIEW] 预览流客户端IP: $clientIp');
      logger.log('预览流客户端IP: $clientIp', tag: 'PREVIEW');
      
      final controller = StreamController<List<int>>();
      const boundary = 'frame';
      
      // 启动预览流
      Future<void> streamPreview() async {
        try {
          logger.log('开始发送预览流', tag: 'PREVIEW');
          controller.add(utf8.encode('--$boundary\r\n'));
          
          int frameCount = 0;
          while (!controller.isClosed && isRunning) {
            // 检查服务器是否还在运行，如果停止则退出循环
            if (!isRunning) {
              print('[PREVIEW] 服务器已停止，停止发送预览帧');
              logger.log('服务器已停止，停止发送预览帧', tag: 'PREVIEW');
              break;
            }
            
            // 检查是否有活跃的连接设备，如果没有则等待
            if (_connectedDevices.isEmpty) {
              // 只在第一次检测到无连接时记录日志
              if (frameCount == 0 || frameCount % 50 == 0) {
                logger.log('没有活跃连接设备，暂停发送预览帧', tag: 'PREVIEW');
              }
              // 等待一段时间后重新检查
              await Future.delayed(const Duration(milliseconds: 500));
              continue;
            }
            
            try {
              // 检查相机是否已初始化，如果未初始化则退出循环
              if (!cameraService.isInitialized) {
                print('[PREVIEW] 相机服务未初始化，停止发送预览帧');
                logger.log('相机服务未初始化，停止发送预览帧', tag: 'PREVIEW');
                break;
              }
              
              final frameData = await cameraService.capturePreviewFrame();
              frameCount++;
              
              if (frameData == null) {
                // 如果相机未初始化，退出循环（服务器可能已停止）
                if (!cameraService.isInitialized || !isRunning) {
                  print('[PREVIEW] 相机服务未初始化或服务器已停止，停止发送预览帧');
                  logger.log('相机服务未初始化或服务器已停止，停止发送预览帧', tag: 'PREVIEW');
                  break;
                }
                // 每10次null才记录一次日志，避免日志过多
                if (frameCount % 10 == 0) {
                  logger.log('预览帧为null (帧计数: $frameCount)', tag: 'PREVIEW');
                }
                // 等待一段时间后重试
                await Future.delayed(const Duration(milliseconds: 100));
                continue;
              }
              
              // 再次检查是否有活跃连接（可能在获取帧的过程中连接断开了）
              if (_connectedDevices.isEmpty) {
                // 只在第一次检测到无连接时记录日志
                if (frameCount == 1 || frameCount % 50 == 0) {
                  logger.log('获取预览帧后没有活跃连接设备，暂停发送', tag: 'PREVIEW');
                }
                await Future.delayed(const Duration(milliseconds: 500));
                continue;
              }
              
              if (!controller.isClosed && isRunning) {
                // 每100帧记录一次日志，避免日志过多
                if (frameCount % 100 == 0) {
                  logger.log('发送预览帧 #$frameCount，大小: ${frameData.length} 字节', tag: 'PREVIEW');
                }
                
                // 注意：不再通过预览流更新连接状态，主要依赖ping心跳来判断客户端是否在线
                // 预览流是长连接，即使客户端断开，服务器端可能无法立即检测到
                // 而ping心跳每5秒一次，30秒超时可以更可靠地检测客户端离线
                
                try {
                  controller.add(utf8.encode('Content-Type: image/jpeg\r\n'));
                  controller.add(utf8.encode('Content-Length: ${frameData.length}\r\n\r\n'));
                  controller.add(frameData);
                  controller.add(utf8.encode('\r\n--$boundary\r\n'));
                } catch (e) {
                  // 如果发送失败（连接已断开），跳出循环
                  print('[PREVIEW] 发送预览帧失败，连接可能已断开: $e');
                  logger.log('发送预览帧失败，连接可能已断开: $e', tag: 'PREVIEW');
                  break;
                }
              } else {
                // controller已关闭或服务器已停止，跳出循环
                print('[PREVIEW] StreamController已关闭或服务器已停止，停止发送预览帧');
                logger.log('StreamController已关闭或服务器已停止，停止发送预览帧', tag: 'PREVIEW');
                break;
              }
              
              // 根据设置的帧率延迟
              await Future.delayed(Duration(milliseconds: 1000 ~/ cameraService.settings.previewFps));
            } catch (e, stackTrace) {
              // 如果服务器已停止，退出循环
              if (!isRunning) {
                print('[PREVIEW] 服务器已停止，停止发送预览帧');
                logger.log('服务器已停止，停止发送预览帧', tag: 'PREVIEW');
                break;
              }
              logger.logError('预览流错误', error: e, stackTrace: stackTrace);
              logger.log('预览流错误，停止发送', tag: 'PREVIEW');
              break;
            }
          }
        } finally {
          logger.log('预览流结束，关闭控制器，客户端IP: $clientIp', tag: 'PREVIEW');
          
          // 预览流断开时，清理连接记录（如果客户端IP有效）
          if (clientIp != 'unknown' && clientIp.isNotEmpty) {
            print('[PREVIEW] 预览流断开，清理连接记录: $clientIp');
            _connectedDevices.remove(clientIp);
            logger.log('预览流断开，已清理连接记录: $clientIp', tag: 'CONNECTION');
            // 检查自动停止状态
            if (_autoStopEnabled && isRunning) {
              print('[AUTO_STOP] 预览流断开，检查自动停止状态');
              _checkAutoStop();
            }
          }
          
          if (!controller.isClosed) {
            await controller.close();
          }
        }
      }
      
      streamPreview();
      
      // 注意：不再监听stream，因为会消费stream导致客户端无法接收数据
      // 连接断开检测主要依赖ping心跳（客户端每5秒ping一次）
      // 当客户端断开时，stream会自动关闭，finally块会执行清理
      
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
        .addHandler(allRoutes);

    // 获取本机IP地址
    _ipAddress = await _getLocalIpAddress();

    // 启动服务器
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
    print('服务器运行在 http://$_ipAddress:$_port');

    // 启动前台服务（保持应用在后台运行时继续工作）
    await _foregroundService.start();
    
    // 加载自动停止设置并启动监控定时器（isRunning是getter，基于_server != null）
    print('[AUTO_STOP] 开始加载自动停止设置...');
    await updateAutoStopSettings();
    print('[AUTO_STOP] 自动停止设置加载完成，enabled=$_autoStopEnabled, minutes=$_autoStopMinutes');

    return _ipAddress ?? 'localhost';
  }

  // 停止服务器
  Future<void> stop() async {
    // 取消自动停止定时器
    _cancelAutoStopTimer();
    _noConnectionStartTime = null;
    
    // 停止前台服务
    await _foregroundService.stop();
    
    await _server?.close(force: true);
    _server = null;
    print('服务器已停止');
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
      print('获取IP地址失败: $e');
    }
    return null;
  }

  String? get ipAddress => _ipAddress;
  int get port => _port;
  bool get isRunning => _server != null;
  List<ConnectedDevice> get connectedDevices => _connectedDevices.values.toList();
  int get connectedDeviceCount => _connectedDevices.length;
}

