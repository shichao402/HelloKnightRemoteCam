import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/connection_settings_service.dart';
import '../services/logger_service.dart';
import 'camera_control_screen.dart';

class DeviceConnectionScreen extends StatefulWidget {
  const DeviceConnectionScreen({Key? key}) : super(key: key);

  @override
  State<DeviceConnectionScreen> createState() => _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState extends State<DeviceConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController(text: '192.168.50.205');
  final _portController = TextEditingController(text: '8080');
  
  final _connectionSettings = ConnectionSettingsService();
  final _logger = ClientLoggerService();
  
  bool _isConnecting = false;
  bool _isAutoConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndAutoConnect();
  }

  Future<void> _loadSettingsAndAutoConnect() async {
    try {
      final settings = await _connectionSettings.getConnectionSettings();
      
      setState(() {
        _hostController.text = settings['host'] as String;
        _portController.text = (settings['port'] as int).toString();
      });

      // 默认自动连接
      _logger.log('尝试自动连接', tag: 'CONNECTION');
      setState(() {
        _isAutoConnecting = true;
      });
      // 延迟一下确保UI已更新
      await Future.delayed(const Duration(milliseconds: 100));
      await _connect(saveSettings: false);
    } catch (e, stackTrace) {
      _logger.logError('加载连接设置失败', error: e, stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect({bool saveSettings = true}) async {
    // 自动连接时跳过表单验证
    if (!_isAutoConnecting && !_formKey.currentState!.validate()) {
      return;
    }

    // 检查必填字段
    if (_hostController.text.isEmpty || 
        _portController.text.isEmpty) {
      if (!_isAutoConnecting && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请填写服务器地址和端口'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isAutoConnecting = false;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final apiService = ApiService(
        host: _hostController.text,
        port: int.parse(_portController.text),
      );

      _logger.log('尝试连接到 ${_hostController.text}:${_portController.text}', tag: 'CONNECTION');

      // 测试连接
      final pingSuccess = await apiService.ping();
      
      if (!mounted) return;

      if (pingSuccess) {
        _logger.log('连接成功', tag: 'CONNECTION');
        
        // 保存连接设置
        if (saveSettings) {
          await _connectionSettings.saveConnectionSettings(
            host: _hostController.text,
            port: int.parse(_portController.text),
            autoConnect: true,
          );
        }

        // 连接成功，跳转到控制页面
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CameraControlScreen(apiService: apiService),
          ),
        );
      } else {
        final errorMsg = '连接失败：无法访问服务器 (${_hostController.text}:${_portController.text})';
        _logger.log(errorMsg, tag: 'CONNECTION');
        // 自动连接失败时也显示错误信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      final errorMsg = '连接错误: $e';
      _logger.logError('连接错误', error: e, stackTrace: stackTrace);
      _logger.log(errorMsg, tag: 'CONNECTION');
      // 自动连接失败时也显示错误信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isAutoConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 自动连接时显示加载界面
    if (_isAutoConnecting) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('连接设备'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text('正在自动连接...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设备'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.camera_alt,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 32),
                const Text(
                  '远程相机控制',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // 服务器地址
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: '服务器IP地址',
                    hintText: '例如: 192.168.1.100',
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入服务器IP地址';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // 端口
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    prefixIcon: Icon(Icons.settings_ethernet),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入端口';
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return '端口必须在1-65535之间';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // 连接按钮
                ElevatedButton(
                  onPressed: _isConnecting ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '连接',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
