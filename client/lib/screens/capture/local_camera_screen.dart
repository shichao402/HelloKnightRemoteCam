import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart' as cam;
import '../../core/sources/sources.dart';
import '../../core/core.dart';
import '../../services/logger_service.dart';

/// 本地摄像头拍摄界面
class LocalCameraScreen extends StatefulWidget {
  const LocalCameraScreen({super.key});

  @override
  State<LocalCameraScreen> createState() => _LocalCameraScreenState();
}

class _LocalCameraScreenState extends State<LocalCameraScreen>
    with WidgetsBindingObserver {
  final ClientLoggerService _logger = ClientLoggerService();

  LocalCameraAdapter? _adapter;

  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _isRecording = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    // 检查平台支持
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      _logger.log('当前桌面平台暂不支持本地摄像头', tag: 'LOCAL_CAM');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '本地摄像头功能暂不支持当前桌面平台\n\n'
              'Flutter camera 插件目前仅支持 Android、iOS 和 Web 平台。\n\n'
              '请使用"手机相机"功能进行拍摄。';
        });
      }
      return;
    }

    try {
      _logger.log('初始化本地摄像头...', tag: 'LOCAL_CAM');

      // 创建适配器并连接
      _adapter = LocalCameraAdapter();
      await _adapter!.connect();

      if (!_adapter!.isConnected) {
        throw Exception(_adapter!.lastError?.message ?? '摄像头连接失败');
      }

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }

      _logger.log('本地摄像头初始化完成', tag: 'LOCAL_CAM');
    } catch (e, stackTrace) {
      _logger.logError('初始化摄像头失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '初始化摄像头失败: $e';
        });
      }
    }
  }

  void _disposeCamera() {
    _adapter?.dispose();
    _adapter = null;
  }

  Future<void> _switchCamera() async {
    if (_adapter == null) return;

    final success = await _adapter!.switchCamera();
    if (success && mounted) {
      setState(() {});
    }
  }

  Future<void> _capture() async {
    if (_adapter == null || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      _logger.log('开始拍照...', tag: 'LOCAL_CAM');
      final result = await _adapter!.capture();

      if (result.success && result.localPath != null) {
        _logger.log('拍照成功: ${result.localPath}', tag: 'LOCAL_CAM');

        // 导入到媒体库
        await _importToMediaLibrary(result.localPath!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('拍照成功，已保存到媒体库'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception(result.error ?? '拍照失败');
      }
    } catch (e) {
      _logger.logError('拍照失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('拍照失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_adapter == null) return;

    try {
      if (_isRecording) {
        _logger.log('停止录像...', tag: 'LOCAL_CAM');
        final result = await _adapter!.stopRecording();

        if (result.success && result.localPath != null) {
          _logger.log('录像成功: ${result.localPath}', tag: 'LOCAL_CAM');

          // 导入到媒体库
          await _importToMediaLibrary(result.localPath!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('录像成功，已保存到媒体库'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        _logger.log('开始录像...', tag: 'LOCAL_CAM');
        await _adapter!.startRecording();
      }

      if (mounted) {
        setState(() {
          _isRecording = !_isRecording;
        });
      }
    } catch (e) {
      _logger.logError('录像操作失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('录像操作失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importToMediaLibrary(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _logger.log('文件不存在，跳过导入: $filePath', tag: 'LOCAL_CAM');
        return;
      }

      final libraryService = MediaLibraryService.instance;
      await libraryService.init();

      // 使用 importFile 方法导入
      final result = await libraryService.importFile(
        filePath,
        sourceId: 'local_camera',
      );

      if (result.success) {
        _logger.log('已导入媒体库: $filePath', tag: 'LOCAL_CAM');
      } else {
        _logger.log('导入媒体库失败: ${result.error}', tag: 'LOCAL_CAM');
      }
    } catch (e) {
      _logger.logError('导入媒体库失败', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('本机摄像头'),
        centerTitle: true,
        actions: [
          if (_adapter?.cameras != null && _adapter!.cameras!.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: _switchCamera,
              tooltip: '切换摄像头',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '正在初始化摄像头...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 预览区域
        Expanded(
          child: _buildPreview(),
        ),

        // 控制栏
        _buildControlBar(),
      ],
    );
  }

  Widget _buildPreview() {
    final controller = _adapter?.cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Text(
          '摄像头未就绪',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: cam.CameraPreview(controller),
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 录像按钮
          _buildControlButton(
            icon: _isRecording ? Icons.stop : Icons.videocam,
            color: _isRecording ? Colors.red : Colors.white,
            onPressed: _toggleRecording,
            label: _isRecording ? '停止' : '录像',
          ),

          // 拍照按钮（主按钮）
          GestureDetector(
            onTap: _isCapturing ? null : _capture,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                color: _isCapturing ? Colors.grey : Colors.white24,
              ),
              child: _isCapturing
                  ? const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.camera,
                      color: Colors.white,
                      size: 36,
                    ),
            ),
          ),

          // 闪光灯按钮（占位）
          _buildControlButton(
            icon: Icons.flash_auto,
            color: Colors.white,
            onPressed: () {
              // TODO: 实现闪光灯切换
            },
            label: '闪光灯',
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          color: color,
          iconSize: 32,
          onPressed: onPressed,
        ),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
