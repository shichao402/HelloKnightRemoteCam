import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../models/file_info.dart';
import '../models/download_task.dart';
import '../widgets/mjpeg_stream_widget.dart';
import 'settings_screen.dart';
import 'file_manager_screen.dart';
import 'client_settings_screen.dart';
import 'device_connection_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/logger_service.dart';

class CameraControlScreen extends StatefulWidget {
  final ApiService apiService;

  const CameraControlScreen({Key? key, required this.apiService})
      : super(key: key);

  @override
  State<CameraControlScreen> createState() => _CameraControlScreenState();
}

class _CameraControlScreenState extends State<CameraControlScreen> {
  bool _isRecording = false;
  bool _isOperating = false;
  List<FileInfo> _pictures = [];
  List<FileInfo> _videos = [];
  late DownloadManager _downloadManager;
  StreamSubscription<List<DownloadTask>>? _downloadSubscription;
  
  // 连接状态管理
  bool _isConnected = true;
  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  Timer? _connectionCheckTimer;
  final ClientLoggerService _logger = ClientLoggerService();

  @override
  void initState() {
    super.initState();
    _downloadManager = DownloadManager(baseUrl: widget.apiService.baseUrl);
    _downloadManager.initialize();
    _refreshFileList();
    _startConnectionCheck();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _reconnectTimer?.cancel();
    _connectionCheckTimer?.cancel();
    super.dispose();
  }
  
  // 开始连接检查
  void _startConnectionCheck() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        final pingSuccess = await widget.apiService.ping();
        if (mounted) {
          setState(() {
            if (!pingSuccess && _isConnected) {
              // 连接断开
              _isConnected = false;
              _logger.log('检测到连接断开', tag: 'CONNECTION');
              _startReconnect();
            } else if (pingSuccess && !_isConnected) {
              // 连接恢复
              _isConnected = true;
              _isReconnecting = false;
              _logger.log('连接已恢复', tag: 'CONNECTION');
              _refreshFileList();
            }
          });
        }
      } catch (e) {
        if (mounted && _isConnected) {
          setState(() {
            _isConnected = false;
            _logger.logError('连接检查失败', error: e);
            _startReconnect();
          });
        }
      }
    });
  }
  
  // 开始重连
  void _startReconnect() {
    if (_isReconnecting) {
      _logger.log('已在重连中，跳过', tag: 'CONNECTION');
      return;
    }
    
    _logger.log('开始重连流程', tag: 'CONNECTION');
    setState(() {
      _isReconnecting = true;
    });
    
    _reconnectTimer?.cancel();
    int reconnectAttempts = 0;
    const maxReconnectAttempts = 20; // 最多尝试20次（约1分钟）
    
    _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      reconnectAttempts++;
      if (reconnectAttempts > maxReconnectAttempts) {
        _logger.log('达到最大重连次数，停止重连', tag: 'CONNECTION');
        timer.cancel();
        _reconnectTimer = null;
        if (mounted) {
          setState(() {
            _isReconnecting = false;
          });
        }
        return;
      }
      
      try {
        _logger.log('尝试重连... (第$reconnectAttempts次)', tag: 'CONNECTION');
        final pingSuccess = await widget.apiService.ping();
        
        if (mounted) {
          if (pingSuccess) {
            setState(() {
              _isConnected = true;
              _isReconnecting = false;
            });
            timer.cancel();
            _reconnectTimer = null;
            _logger.log('重连成功', tag: 'CONNECTION');
            _refreshFileList();
          } else {
            _logger.log('重连失败：ping返回false (第$reconnectAttempts次)', tag: 'CONNECTION');
          }
        }
      } catch (e) {
        _logger.log('重连失败: $e (第$reconnectAttempts次)', tag: 'CONNECTION');
      }
    });
  }
  
  // 手动重连
  Future<void> _manualReconnect() async {
    setState(() {
      _isReconnecting = true;
    });
    
    try {
      final pingSuccess = await widget.apiService.ping();
      if (mounted) {
        setState(() {
          _isConnected = pingSuccess;
          _isReconnecting = false;
        });
        
        if (pingSuccess) {
          _showSuccess('重连成功');
          _refreshFileList();
        } else {
          _showError('重连失败，请检查服务器状态');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
        _showError('重连失败: $e');
      }
    }
  }
  
  // 返回连接页面
  void _returnToConnectionScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const DeviceConnectionScreen()),
      (route) => false,
    );
  }

  Future<void> _refreshFileList() async {
    try {
      final result = await widget.apiService.getFileList();
      if (result['success'] && mounted) {
        setState(() {
          _pictures = result['pictures'] as List<FileInfo>;
          _videos = result['videos'] as List<FileInfo>;
        });
      }
    } catch (e) {
      _showError('刷新文件列表失败: $e');
    }
  }

  Future<void> _takePicture() async {
    setState(() {
      _isOperating = true;
    });

    try {
      final result = await widget.apiService.capture();
      if (result['success']) {
        _showSuccess('拍照成功');
        await _refreshFileList();
        
        // 自动下载最新照片
        if (_pictures.isNotEmpty) {
          final latestPicture = _pictures.first; // 最新的照片在第一位
          await _autoDownloadPicture(latestPicture);
        }
      } else {
        _showError('拍照失败: ${result['error']}');
      }
    } catch (e) {
      _showError('拍照失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  Future<void> _autoDownloadPicture(FileInfo file) async {
    try {
      // 检查是否已经在下载中或已完成
      final existingTask = await _downloadManager.findTaskByFileName(file.name);
      
      if (existingTask != null) {
        if (existingTask.status == DownloadStatus.downloading || 
            existingTask.status == DownloadStatus.pending) {
          // 已经在下载中
          return;
        }
        
        if (existingTask.status == DownloadStatus.completed) {
          // 已经下载完成
          if (mounted) {
            _showDownloadSuccess(file.name, existingTask.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
          return;
        }
      }
      
      final taskId = await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );
      
      // 取消之前的订阅
      _downloadSubscription?.cancel();
      
      // 监听下载完成（只监听一次）
      _downloadSubscription = _downloadManager.tasksStream.listen((tasks) {
        final task = tasks.firstWhere(
          (t) => t.id == taskId,
          orElse: () => tasks.first,
        );
        
        if (task.status == DownloadStatus.completed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showDownloadSuccess(file.name, task.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
        } else if (task.status == DownloadStatus.failed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showError('下载失败: ${file.name}');
          }
        }
      });
    } catch (e) {
      final logger = ClientLoggerService();
      logger.logError('自动下载失败', error: e);
    }
  }

  Future<void> _showDownloadSuccess(String fileName, String filePath) async {
    final directory = await getApplicationDocumentsDirectory();
    final downloadDir = path.join(directory.path, 'downloads');
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('下载完成: $fileName'),
            Text(
              '保存位置: $downloadDir',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '打开文件夹',
          onPressed: () {
            _openFolder(downloadDir);
          },
        ),
      ),
    );
  }

  Future<void> _openFolder(String folderPath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [folderPath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [folderPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [folderPath]);
      }
    } catch (e) {
      _showError('打开文件夹失败: $e');
    }
  }

  Future<void> _toggleRecording() async {
    setState(() {
      _isOperating = true;
    });

    try {
      final result = _isRecording
          ? await widget.apiService.stopRecording()
          : await widget.apiService.startRecording();

      if (result['success']) {
        final wasRecording = _isRecording;
        setState(() {
          _isRecording = !_isRecording;
        });
        _showSuccess(_isRecording ? '录像已开始' : '录像已停止');
        
        if (!wasRecording && _isRecording) {
          // 录像已开始
        } else if (wasRecording && !_isRecording) {
          // 录像已停止，刷新文件列表并自动下载最新视频
          await _refreshFileList();
          
          if (_videos.isNotEmpty) {
            final latestVideo = _videos.first; // 最新的视频在第一位
            await _autoDownloadVideo(latestVideo);
          }
        }
      } else {
        _showError('操作失败: ${result['error']}');
      }
    } catch (e) {
      _showError('操作失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  Future<void> _autoDownloadVideo(FileInfo file) async {
    try {
      // 检查是否已经在下载中或已完成
      final existingTask = await _downloadManager.findTaskByFileName(file.name);
      
      if (existingTask != null) {
        if (existingTask.status == DownloadStatus.downloading || 
            existingTask.status == DownloadStatus.pending) {
          // 已经在下载中
          return;
        }
        
        if (existingTask.status == DownloadStatus.completed) {
          // 已经下载完成
          if (mounted) {
            _showDownloadSuccess(file.name, existingTask.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
          return;
        }
      }
      
      final taskId = await _downloadManager.addDownload(
        remoteFilePath: file.path,
        fileName: file.name,
      );
      
      // 取消之前的订阅
      _downloadSubscription?.cancel();
      
      // 监听下载完成（只监听一次）
      _downloadSubscription = _downloadManager.tasksStream.listen((tasks) {
        final task = tasks.firstWhere(
          (t) => t.id == taskId,
          orElse: () => tasks.first,
        );
        
        if (task.status == DownloadStatus.completed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showDownloadSuccess(file.name, task.localFilePath);
            // 自动刷新文件列表
            _refreshFileList();
          }
        } else if (task.status == DownloadStatus.failed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
          if (mounted) {
            _showError('下载失败: ${file.name}');
          }
        }
      });
    } catch (e) {
      final logger = ClientLoggerService();
      logger.logError('自动下载视频失败', error: e);
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _navigateToSettings() async {
    // 显示选择对话框：相机设置或应用设置
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('相机设置'),
              subtitle: const Text('调整相机参数和质量设置'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('应用设置'),
              subtitle: const Text('调试模式和日志设置'),
              onTap: () => Navigator.of(context).pop('app'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (choice == 'camera') {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SettingsScreen(apiService: widget.apiService),
        ),
      );
      
      // 如果设置已更改，可能需要刷新某些状态
      if (result == true) {
        // 设置已更新
      }
    } else if (choice == 'app') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ClientSettingsScreen(),
        ),
      );
    }
  }

  void _navigateToFileManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FileManagerScreen(apiService: widget.apiService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('远程相机控制'),
            const SizedBox(width: 8),
            // 连接状态指示器
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
            if (_isReconnecting) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // 重连按钮
          if (!_isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isReconnecting ? null : _manualReconnect,
              tooltip: '重连',
            ),
          // 返回连接页面按钮
          if (!_isConnected)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _returnToConnectionScreen,
              tooltip: '返回连接页面',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
            tooltip: '设置',
          ),
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: _navigateToFileManager,
            tooltip: '文件管理',
          ),
        ],
      ),
      body: Column(
        children: [
          // 预览区域
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Center(
                      child: MjpegStreamWidget(
                        streamUrl: widget.apiService.getPreviewStreamUrl(),
                        fit: BoxFit.contain,
                      ),
                    ),
                    if (_isRecording)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.fiber_manual_record,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '录像中',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 控制按钮区域
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 拍照按钮
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isOperating || _isRecording ? null : _takePicture,
                    icon: const Icon(Icons.camera),
                    label: const Text('拍照'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // 录像按钮
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isOperating ? null : _toggleRecording,
                    icon: Icon(_isRecording ? Icons.stop : Icons.videocam),
                    label: Text(_isRecording ? '停止录像' : '开始录像'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _isRecording ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 文件快速预览
          Expanded(
            flex: 2,
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '最近文件',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _refreshFileList,
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildFileQuickList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileQuickList() {
    final allFiles = [..._pictures, ..._videos]
      ..sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    
    if (allFiles.isEmpty) {
      return const Center(
        child: Text('暂无文件'),
      );
    }

    final recentFiles = allFiles.take(5).toList();

    return ListView.builder(
      itemCount: recentFiles.length,
      itemBuilder: (context, index) {
        final file = recentFiles[index];
        return ListTile(
          leading: Icon(
            file.isVideo ? Icons.videocam : Icons.image,
            color: file.isVideo ? Colors.red : Colors.blue,
          ),
          title: Text(file.name),
          subtitle: Text(file.formattedSize),
          trailing: const Icon(Icons.chevron_right),
          onTap: _navigateToFileManager,
        );
      },
    );
  }
}

