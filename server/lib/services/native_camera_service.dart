import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'logger_service.dart';

/// 原生相机服务 - 使用Android Camera2 API实现同时录制和预览
class NativeCameraService {
  static const MethodChannel _methodChannel = MethodChannel('com.example.remote_cam_server/camera2');
  static const EventChannel _eventChannel = EventChannel('com.example.remote_cam_server/preview_stream');
  
  final LoggerService _logger = LoggerService();
  
  StreamSubscription<dynamic>? _previewSubscription;
  Uint8List? _lastPreviewFrame;
  bool _isInitialized = false;
  bool _isRecording = false;
  
  // 预览帧回调
  Function(Uint8List)? onPreviewFrame;
  
  // 检查是否有活跃客户端连接的回调函数（返回true表示有活跃连接）
  bool Function()? _hasActiveClientsCallback;
  
  /// 初始化原生相机
  Future<bool> initialize(String cameraId, {int previewWidth = 640, int previewHeight = 480}) async {
    try {
      _logger.logCamera('初始化原生相机', details: '相机ID: $cameraId, 预览尺寸: ${previewWidth}x$previewHeight');
      
      // 先启动预览流监听（EventChannel的listen是同步注册的，不需要延迟）
      _startPreviewStream();
      
      final result = await _methodChannel.invokeMethod<bool>('initialize', {
        'cameraId': cameraId,
        'previewWidth': previewWidth,
        'previewHeight': previewHeight,
      });
      
      if (result == true) {
        _isInitialized = true;
        _logger.logCamera('原生相机初始化成功');
        return true;
      } else {
        _logger.logError('原生相机初始化失败', error: Exception('原生方法返回false，相机ID: $cameraId, 预览尺寸: ${previewWidth}x$previewHeight'));
        _previewSubscription?.cancel();
        _previewSubscription = null;
        return false;
      }
    } on PlatformException catch (e, stackTrace) {
      _logger.logError('初始化原生相机PlatformException', error: e, stackTrace: stackTrace);
      _logger.logError('错误代码: ${e.code}, 错误消息: ${e.message}, 错误详情: ${e.details}');
      _previewSubscription?.cancel();
      _previewSubscription = null;
      return false;
    } catch (e, stackTrace) {
      _logger.logError('初始化原生相机异常', error: e, stackTrace: stackTrace);
      _previewSubscription?.cancel();
      _previewSubscription = null;
      return false;
    }
  }
  
  /// 设置检查活跃客户端连接的回调函数
  void setHasActiveClientsCallback(bool Function()? callback) {
    _hasActiveClientsCallback = callback;
  }
  
  /// 启动预览流
  void _startPreviewStream() {
    _previewSubscription?.cancel();
    
    _logger.logCamera('启动预览流监听', details: '等待EventChannel数据');
    
    _previewSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        try {
          if (data is Uint8List) {
            // 只有在有活跃客户端连接时才处理预览帧数据
            if (_hasActiveClientsCallback != null && !_hasActiveClientsCallback!()) {
              // 没有活跃客户端，跳过处理（不记录日志，不更新_lastPreviewFrame）
              return;
            }
            
            // 数据已经是JPEG格式（Android端已转换）
            // 不记录每帧日志，避免日志过多
            _processPreviewFrame(data);
          } else {
            _logger.log('预览帧数据类型不正确: ${data.runtimeType}', tag: 'PREVIEW');
          }
        } catch (e, stackTrace) {
          _logger.logError('处理预览帧失败', error: e, stackTrace: stackTrace);
        }
      },
      onError: (error) {
        _logger.logError('预览流错误', error: error);
      },
      cancelOnError: false, // 不因错误取消订阅
    );
  }

  /// 恢复预览流（应用切回前台时调用）
  Future<void> resumePreview() async {
    if (!_isInitialized) {
      _logger.logCamera('相机未初始化，无法恢复预览流');
      return;
    }

    try {
      _logger.logCamera('恢复预览流', details: '重新启动EventChannel监听');
      
      // 重新启动预览流监听
      _startPreviewStream();
      
      // 调用原生方法重新启动预览（如果原生端支持）
      try {
        await _methodChannel.invokeMethod('resumePreview');
        _logger.logCamera('已调用原生方法恢复预览');
      } catch (e) {
        // 如果原生端不支持resumePreview方法，忽略错误
        _logger.log('原生端不支持resumePreview方法，跳过', tag: 'PREVIEW');
      }
    } catch (e, stackTrace) {
      _logger.logError('恢复预览流失败', error: e, stackTrace: stackTrace);
    }
  }
  
  /// 处理预览帧（数据已经是JPEG格式）
  void _processPreviewFrame(Uint8List jpegData) {
    // Android端已经将YUV转换为JPEG，直接使用
    _lastPreviewFrame = jpegData;
    onPreviewFrame?.call(jpegData);
  }
  
  /// 开始录制
  Future<bool> startRecording(String outputPath) async {
    try {
      if (!_isInitialized) {
        _logger.logError('开始录制失败', error: Exception('相机未初始化'));
        return false;
      }
      
      if (_isRecording) {
        _logger.logError('开始录制失败', error: Exception('已在录制中'));
        return false;
      }
      
      _logger.logCamera('开始录制（原生相机）', details: '输出路径: $outputPath');
      
      final result = await _methodChannel.invokeMethod<bool>('startRecording', {
        'outputPath': outputPath,
      });
      
      if (result == true) {
        _isRecording = true;
        _logger.logCamera('录制已开始（原生相机）', details: '输出路径: $outputPath');
        return true;
      } else {
        _logger.logError('开始录制失败', error: Exception('返回false'));
        return false;
      }
    } catch (e, stackTrace) {
      _logger.logError('开始录制异常', error: e, stackTrace: stackTrace);
      return false;
    }
  }
  
  /// 停止录制
  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) {
        _logger.logError('停止录制失败', error: Exception('未在录制中'));
        return null;
      }
      
      _logger.logCamera('停止录制（原生相机）', details: '');
      
      final path = await _methodChannel.invokeMethod<String>('stopRecording');
      
      _isRecording = false;
      
      if (path != null) {
        _logger.logCamera('录制已停止（原生相机）', details: '文件路径: $path');
        return path;
      } else {
        _logger.logError('停止录制失败', error: Exception('返回null'));
        return null;
      }
    } catch (e, stackTrace) {
      _logger.logError('停止录制异常', error: e, stackTrace: stackTrace);
      return null;
    }
  }
  
  /// 获取最后一帧预览
  Uint8List? getLastPreviewFrame() {
    return _lastPreviewFrame;
  }
  
  /// 拍照
  Future<String?> takePicture(String outputPath) async {
    try {
      if (!_isInitialized) {
        _logger.logError('拍照失败', error: Exception('相机未初始化'));
        return null;
      }
      
      _logger.logCamera('开始拍照（原生相机）', details: '输出路径: $outputPath');
      
      final path = await _methodChannel.invokeMethod<String>('takePicture', {
        'outputPath': outputPath,
      });
      
      if (path != null) {
        _logger.logCamera('拍照成功（原生相机）', details: '文件路径: $path');
        return path;
      } else {
        _logger.logError('拍照失败', error: Exception('返回null'));
        return null;
      }
    } catch (e, stackTrace) {
      _logger.logError('拍照异常', error: e, stackTrace: stackTrace);
      return null;
    }
  }
  
  /// 释放资源
  Future<void> release() async {
    try {
      _previewSubscription?.cancel();
      _previewSubscription = null;
      
      await _methodChannel.invokeMethod('release');
      
      _isInitialized = false;
      _isRecording = false;
      _lastPreviewFrame = null;
      
      _logger.logCamera('原生相机资源已释放');
    } catch (e, stackTrace) {
      _logger.logError('释放原生相机资源失败', error: e, stackTrace: stackTrace);
    }
  }
  
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
}

