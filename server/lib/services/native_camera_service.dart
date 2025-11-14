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
  
  /// 初始化原生相机
  Future<bool> initialize(String cameraId, {int previewWidth = 640, int previewHeight = 480}) async {
    try {
      _logger.logCamera('初始化原生相机', details: '相机ID: $cameraId, 预览尺寸: ${previewWidth}x$previewHeight');
      
      // 先启动预览流监听（确保EventChannel监听已启动）
      _startPreviewStream();
      
      // 等待一小段时间，确保EventChannel监听已启动
      await Future.delayed(const Duration(milliseconds: 100));
      
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
        _logger.logError('原生相机初始化失败', error: Exception('返回false'));
        _previewSubscription?.cancel();
        _previewSubscription = null;
        return false;
      }
    } catch (e, stackTrace) {
      _logger.logError('初始化原生相机异常', error: e, stackTrace: stackTrace);
      _previewSubscription?.cancel();
      _previewSubscription = null;
      return false;
    }
  }
  
  /// 启动预览流
  void _startPreviewStream() {
    _previewSubscription?.cancel();
    
    _logger.logCamera('启动预览流监听', details: '等待EventChannel数据');
    
    _previewSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        try {
          if (data is Uint8List) {
            _logger.logCamera('收到预览帧数据', details: '大小: ${data.length} 字节');
            // 数据已经是JPEG格式（Android端已转换）
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

