import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'camera_service.dart';
import 'settings_service.dart';
import 'logger_service.dart';
import '../models/camera_settings.dart';
import '../models/camera_status.dart';

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
  
  HttpServer? _server;
  String? _ipAddress;
  int _port = 8080;
  final Map<String, ConnectedDevice> _connectedDevices = {};

  HttpServerService({
    required this.cameraService,
    required this.settingsService,
  });

  // 更新连接设备信息
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
    
    // 清理5分钟未活动的设备
    final removed = <String>[];
    _connectedDevices.removeWhere((ip, device) {
      final inactive = now.difference(device.lastActivity).inMinutes > 5;
      if (inactive) {
        removed.add(ip);
        logger.log('设备断开连接: $ip (超时)', tag: 'CONNECTION');
      }
      return inactive;
    });
    
    // 如果有变化，通知监听者（如果实现了）
    if (wasNew || removed.isNotEmpty) {
      _notifyListeners();
    }
  }
  
  // 通知监听者（用于UI更新）
  void _notifyListeners() {
    // 这个方法可以被扩展为使用Stream或ValueNotifier
    // 目前UI通过定时刷新来更新
  }

  // 启动服务器
  Future<String> start(int port) async {
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
          
          // OPTIONS 请求直接通过（CORS 预检），但不记录连接
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
              'Access-Control-Allow-Headers': 'Origin, Content-Type',
            });
          }

          // 记录连接设备（排除OPTIONS请求）
          _updateConnectedDevice(clientIp);
          
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
      logger.log('收到ping请求，来自: $clientIp', tag: 'CONNECTION');
      
      // ping请求也会通过中间件更新连接设备，这里不需要重复调用
      return Response.ok('pong');
    });

    // API端点
    final apiRouter = Router();

    // 拍照
    apiRouter.post('/capture', (Request request) async {
      try {
        logger.logCamera('开始拍照');
        final filePath = await cameraService.takePicture();
        logger.logCamera('拍照成功', details: filePath);
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
      try {
        logger.logCamera('开始录像');
        final filePath = await cameraService.startRecording();
        logger.logCamera('录像开始成功', details: filePath);
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
      try {
        logger.logCamera('停止录像');
        final filePath = await cameraService.stopRecording();
        logger.logCamera('录像停止成功', details: filePath);
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

    // 下载文件（支持Range请求用于断点续传）
    apiRouter.get('/file/download', (Request request) async {
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

        // 检查是否为Range请求
        final rangeHeader = request.headers['range'];
        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          // 处理断点续传
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

        // 完整文件下载
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
      
      final controller = StreamController<List<int>>();
      const boundary = 'frame';
      
      // 启动预览流
      Future<void> streamPreview() async {
        try {
          logger.log('开始发送预览流', tag: 'PREVIEW');
          controller.add(utf8.encode('--$boundary\r\n'));
          
          int frameCount = 0;
          while (!controller.isClosed) {
            try {
              final frameData = await cameraService.capturePreviewFrame();
              frameCount++;
              
              if (frameData == null) {
                logger.log('预览帧为null (帧计数: $frameCount)', tag: 'PREVIEW');
                // 如果相机未初始化，等待一段时间后重试
                await Future.delayed(const Duration(milliseconds: 500));
                continue;
              }
              
              if (!controller.isClosed) {
                logger.log('发送预览帧 #$frameCount，大小: ${frameData.length} 字节', tag: 'PREVIEW');
                controller.add(utf8.encode('Content-Type: image/jpeg\r\n'));
                controller.add(utf8.encode('Content-Length: ${frameData.length}\r\n\r\n'));
                controller.add(frameData);
                controller.add(utf8.encode('\r\n--$boundary\r\n'));
              }
              
              // 根据设置的帧率延迟
              await Future.delayed(Duration(milliseconds: 1000 ~/ cameraService.settings.previewFps));
            } catch (e, stackTrace) {
              logger.logError('预览流错误', error: e, stackTrace: stackTrace);
              logger.log('预览流错误，停止发送', tag: 'PREVIEW');
              break;
            }
          }
        } finally {
          logger.log('预览流结束，关闭控制器', tag: 'PREVIEW');
          if (!controller.isClosed) {
            await controller.close();
          }
        }
      }
      
      streamPreview();
      
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

    return _ipAddress ?? 'localhost';
  }

  // 停止服务器
  Future<void> stop() async {
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

