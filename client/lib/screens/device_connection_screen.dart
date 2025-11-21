import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/api_service_manager.dart';
import '../services/connection_settings_service.dart';
import '../services/device_config_service.dart';
import '../services/logger_service.dart';
import '../services/update_service.dart';
import '../models/connection_error.dart';
import 'camera_control_screen.dart';
import 'client_settings_screen.dart';

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
  final _deviceConfigService = DeviceConfigService();
  final _logger = ClientLoggerService();
  final _updateService = UpdateService();

  bool _isConnecting = false;
  bool _isAutoConnecting = false;
  bool _autoConnectEnabled = true;
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndAutoConnect();
    _checkForUpdate();
  }
  
  Future<void> _checkForUpdate() async {
    final updateInfo = await _updateService.getSavedUpdateInfo();
    if (mounted) {
      setState(() {
        _updateInfo = updateInfo;
      });
    }
  }

  Future<void> _loadSettingsAndAutoConnect() async {
    try {
      final settings = await _connectionSettings.getConnectionSettings();

      setState(() {
        _hostController.text = settings['host'] as String;
        _portController.text = (settings['port'] as int).toString();
        _autoConnectEnabled = settings['autoConnect'] as bool;
      });

      // 检查是否跳过本次自动连接（主动断开连接后）
      final shouldSkip = await _connectionSettings.shouldSkipAutoConnectOnce();
      if (shouldSkip) {
        // 清除跳过标志，下次启动时恢复自动连接
        await _connectionSettings.setSkipAutoConnectOnce(false);
        _logger.log('跳过本次自动连接（用户主动断开）', tag: 'CONNECTION');
        return;
      }

      // 如果启用了自动连接，则自动连接
      if (_autoConnectEnabled) {
        _logger.log('尝试自动连接', tag: 'CONNECTION');
        setState(() {
          _isAutoConnecting = true;
        });
        // 使用postFrameCallback确保UI已更新后再连接
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _connect(saveSettings: false);
        });
      }
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
    if (_hostController.text.isEmpty || _portController.text.isEmpty) {
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

      // 注册到全局管理器，以便在应用退出时能够优雅关闭
      ApiServiceManager().setCurrentApiService(apiService);

      _logger.log('尝试连接到 ${_hostController.text}:${_portController.text}',
          tag: 'CONNECTION');

      // 测试连接
      final pingError = await apiService.ping();

      if (!mounted) return;

      if (pingError == null) {
        // 连接成功
        _logger.log('连接成功', tag: 'CONNECTION');

        // 清除跳过自动连接标志（连接成功后恢复自动连接）
        await _connectionSettings.setSkipAutoConnectOnce(false);

        // 保存连接设置
        if (saveSettings) {
          await _connectionSettings.saveConnectionSettings(
            host: _hostController.text,
            port: int.parse(_portController.text),
            autoConnect: _autoConnectEnabled,
          );
        }

        // 连接WebSocket并获取设备信息
        await apiService.connectWebSocket();

        // 监听连接失败通知
        StreamSubscription? connectionFailedSubscription;
        connectionFailedSubscription = apiService.webSocketNotifications?.listen((notification) {
          final event = notification['event'] as String?;
          if (event == 'connection_failed') {
            final data = notification['data'] as Map<String, dynamic>?;
            
            // 尝试从错误对象中获取ConnectionError
            ConnectionError? connectionError;
            if (data?['error'] != null && data!['error'] is Map) {
              try {
                final errorData = data['error'] as Map<String, dynamic>;
                connectionError = ConnectionError(
                  code: ConnectionErrorCode.values.firstWhere(
                    (e) => e.name == errorData['code'],
                    orElse: () => ConnectionErrorCode.unknown,
                  ),
                  message: errorData['message'] as String? ?? '连接失败',
                  details: errorData['details'] as String?,
                  minRequiredVersion: errorData['minRequiredVersion'] as String?,
                  clientVersion: errorData['clientVersion'] as String?,
                  serverVersion: errorData['serverVersion'] as String?,
                );
              } catch (e) {
                _logger.logError('解析ConnectionError失败', error: e);
              }
            }
            
            // 如果没有解析到ConnectionError，使用旧格式
            if (connectionError == null) {
              final message = data?['message'] as String? ?? '连接失败';
              final minRequiredVersion = data?['minRequiredVersion'] as String?;
              connectionError = ConnectionError(
                code: (data?['isAuthFailure'] as bool? ?? false)
                    ? ConnectionErrorCode.versionIncompatible
                    : ConnectionErrorCode.networkError,
                message: message,
                minRequiredVersion: minRequiredVersion,
              );
            }
            
            _logger.log('连接失败: ${connectionError.code.name} - ${connectionError.message}', tag: 'CONNECTION');
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(connectionError.getUserFriendlyMessage()),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 8),
                ),
              );
            }
            
            setState(() {
              _isConnecting = false;
              _isAutoConnecting = false;
            });
            
            connectionFailedSubscription?.cancel();
          }
        });

        // 检查WebSocket是否真的连接成功（等待一小段时间）
        await Future.delayed(const Duration(milliseconds: 500));
        
        // 如果WebSocket未连接，说明连接失败
        if (!apiService.isWebSocketConnected) {
          _logger.log('WebSocket连接失败', tag: 'CONNECTION');
          connectionFailedSubscription?.cancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('连接失败：服务器拒绝了连接，可能是版本不兼容'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
          setState(() {
            _isConnecting = false;
            _isAutoConnecting = false;
          });
          return;
        }

        // 获取设备信息
        String? deviceModel;
        try {
          final deviceInfoResult = await apiService.getDeviceInfo();
          if (deviceInfoResult['success'] == true &&
              deviceInfoResult['deviceInfo'] != null) {
            final deviceInfo =
                deviceInfoResult['deviceInfo'] as Map<String, dynamic>;
            deviceModel = deviceInfo['model'] as String?;
            _logger.log('获取设备信息成功，型号: $deviceModel', tag: 'CONNECTION');

            // 注册设备（设置独占连接）
            if (deviceModel != null && deviceModel.isNotEmpty) {
              final registerResult = await apiService.registerDevice(deviceModel);
              // 检查注册是否成功，如果失败（可能是版本不兼容），停止连接流程
              if (registerResult['success'] != true) {
                final error = registerResult['error'] as String?;
                _logger.log('设备注册失败: $error', tag: 'CONNECTION');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('连接失败: ${error ?? "未知错误"}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
                setState(() {
                  _isConnecting = false;
                });
                return;
              }
            }
          }
        } catch (e, stackTrace) {
          _logger.logError('获取设备信息失败', error: e, stackTrace: stackTrace);
        }

        // 获取并应用保存的设备配置
        if (deviceModel != null && deviceModel.isNotEmpty) {
          try {
            final savedConfig =
                await _deviceConfigService.getDeviceConfig(deviceModel);
            if (savedConfig != null) {
              _logger.log('找到保存的设备配置，应用配置', tag: 'CONNECTION');
              // 应用配置到服务器
              await apiService.updateSettings(savedConfig);
              _logger.log('设备配置已应用', tag: 'CONNECTION');
            } else {
              _logger.log('未找到保存的设备配置，使用默认配置', tag: 'CONNECTION');
            }
          } catch (e, stackTrace) {
            _logger.logError('应用设备配置失败', error: e, stackTrace: stackTrace);
          }
        }

        // 连接成功，跳转到控制页面
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CameraControlScreen(apiService: apiService),
          ),
        );
      } else {
        // 连接失败，显示详细的错误信息
        final errorMsg = pingError.getUserFriendlyMessage();
        _logger.log('连接失败: ${pingError.code.name} - ${pingError.message}', tag: 'CONNECTION');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        
        setState(() {
          _isConnecting = false;
          _isAutoConnecting = false;
        });
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
        actions: [
          if (_updateInfo != null)
            IconButton(
              icon: const Badge(
                label: Text('新'),
                child: Icon(Icons.system_update),
              ),
              onPressed: () async {
                final success = await _updateService.openDownloadUrl(_updateInfo!.downloadUrl);
                if (mounted && !success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('无法打开下载链接'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              tooltip: '有新版本可用: ${_updateInfo!.version}',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ClientSettingsScreen(),
                ),
              );
            },
            tooltip: '应用设置',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_updateInfo != null)
            Container(
              width: double.infinity,
              color: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: InkWell(
                onTap: () async {
                  final success = await _updateService.openDownloadUrl(_updateInfo!.downloadUrl);
                  if (mounted && !success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('无法打开下载链接'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    const Icon(Icons.system_update, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '有新版本可用: ${_updateInfo!.version}，点击下载',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.white),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Center(
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

                // 自动连接选项
                CheckboxListTile(
                  value: _autoConnectEnabled,
                  onChanged: (value) {
                    setState(() {
                      _autoConnectEnabled = value ?? true;
                    });
                    // 保存自动连接设置
                    _connectionSettings.saveConnectionSettings(
                      host: _hostController.text,
                      port: int.tryParse(_portController.text) ?? 8080,
                      autoConnect: _autoConnectEnabled,
                    );
                  },
                  title: const Text('自动连接服务器'),
                  subtitle: const Text('启动时自动连接到上次连接的服务器'),
                  controlAffinity: ListTileControlAffinity.leading,
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
          ),
        ],
      ),
    );
  }
}
