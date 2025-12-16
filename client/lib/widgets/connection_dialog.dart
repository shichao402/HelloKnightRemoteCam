import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/api_service_manager.dart';
import '../services/connection_settings_service.dart';
import '../services/device_config_service.dart';
import '../services/logger_service.dart';
import '../models/connection_error.dart';

/// 连接对话框
/// 
/// 用于连接远端相机服务器，以对话框形式显示，不影响导航
class ConnectionDialog extends StatefulWidget {
  /// 连接成功后的回调
  final VoidCallback? onConnected;
  
  const ConnectionDialog({super.key, this.onConnected});

  /// 显示连接对话框
  static Future<bool?> show(BuildContext context, {VoidCallback? onConnected}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConnectionDialog(onConnected: onConnected),
    );
  }

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController(text: '192.168.50.205');
  final _portController = TextEditingController(text: '8080');

  final _connectionSettings = ConnectionSettingsService();
  final _deviceConfigService = DeviceConfigService();
  final _logger = ClientLoggerService();

  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _connectionSettings.getConnectionSettings();
      setState(() {
        _hostController.text = settings['host'] as String;
        _portController.text = (settings['port'] as int).toString();
      });
    } catch (e, stackTrace) {
      _logger.logError('加载连接设置失败', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final apiService = ApiService(
        host: _hostController.text,
        port: int.parse(_portController.text),
      );

      // 注册到全局管理器
      ApiServiceManager().setCurrentApiService(apiService);

      _logger.log('尝试连接到 ${_hostController.text}:${_portController.text}',
          tag: 'CONNECTION');

      // 测试连接
      final pingError = await apiService.ping();

      if (!mounted) return;

      if (pingError == null) {
        // 连接成功（ping已经建立了WebSocket连接）
        _logger.log('连接成功', tag: 'CONNECTION');

        // 保存连接设置
        await _connectionSettings.saveConnectionSettings(
          host: _hostController.text,
          port: int.parse(_portController.text),
          autoConnect: true,
        );

        // 检查WebSocket是否真的连接成功
        if (!apiService.isWebSocketConnected) {
          _logger.log('WebSocket连接失败', tag: 'CONNECTION');
          setState(() {
            _isConnecting = false;
            _errorMessage = '连接失败：服务器拒绝了连接';
          });
          return;
        }

        // 获取设备信息并注册
        String? deviceModel;
        try {
          final deviceInfoResult = await apiService.getDeviceInfo();
          if (deviceInfoResult['success'] == true &&
              deviceInfoResult['deviceInfo'] != null) {
            final deviceInfo =
                deviceInfoResult['deviceInfo'] as Map<String, dynamic>;
            deviceModel = deviceInfo['model'] as String?;
            _logger.log('获取设备信息成功，型号: $deviceModel', tag: 'CONNECTION');

            // 注册设备
            if (deviceModel != null && deviceModel.isNotEmpty) {
              final registerResult = await apiService.registerDevice(deviceModel);
              if (registerResult['success'] != true) {
                final error = registerResult['error'] as String?;
                _logger.log('设备注册失败: $error', tag: 'CONNECTION');
                setState(() {
                  _isConnecting = false;
                  _errorMessage = '连接失败: ${error ?? "未知错误"}';
                });
                return;
              }
            }
          }
        } catch (e, stackTrace) {
          _logger.logError('获取设备信息失败', error: e, stackTrace: stackTrace);
        }

        // 应用保存的设备配置
        if (deviceModel != null && deviceModel.isNotEmpty) {
          try {
            final savedConfig =
                await _deviceConfigService.getDeviceConfig(deviceModel);
            if (savedConfig != null) {
              _logger.log('找到保存的设备配置，应用配置', tag: 'CONNECTION');
              await apiService.updateSettings(savedConfig);
              _logger.log('设备配置已应用', tag: 'CONNECTION');
            }
          } catch (e, stackTrace) {
            _logger.logError('应用设备配置失败', error: e, stackTrace: stackTrace);
          }
        }

        // 连接成功，关闭对话框
        if (mounted) {
          widget.onConnected?.call();
          Navigator.of(context).pop(true);
        }
      } else {
        // 连接失败
        final errorMsg = pingError.getUserFriendlyMessage();
        _logger.log('连接失败: ${pingError.code.name} - ${pingError.message}',
            tag: 'CONNECTION');

        setState(() {
          _isConnecting = false;
          _errorMessage = errorMsg;
        });
      }
    } catch (e, stackTrace) {
      _logger.logError('连接错误', error: e, stackTrace: stackTrace);
      setState(() {
        _isConnecting = false;
        _errorMessage = '连接错误: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.phone_android, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          const Text('连接远端相机'),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 错误提示
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
                enabled: !_isConnecting,
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
                enabled: !_isConnecting,
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
              const SizedBox(height: 8),
              Text(
                '请确保手机端已启动远程相机服务',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isConnecting ? null : _connect,
          child: _isConnecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('连接'),
        ),
      ],
    );
  }
}
