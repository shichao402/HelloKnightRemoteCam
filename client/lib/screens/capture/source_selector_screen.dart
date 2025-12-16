import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/sources/sources.dart';
import '../device_connection_screen.dart';
import 'local_camera_screen.dart';

/// 拍摄来源选择界面
///
/// 让用户选择使用哪种拍摄来源：
/// - 本地摄像头（客户端设备）
/// - 手机相机（远程连接）
class SourceSelectorScreen extends StatelessWidget {
  const SourceSelectorScreen({super.key});

  /// 检查本地摄像头是否可用（仅 Android、iOS、Web 支持）
  bool get _isLocalCameraSupported =>
      Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择拍摄来源'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                '请选择拍摄设备',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '您可以使用本机摄像头或连接手机进行拍摄',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSourceCard(
                      context,
                      icon: Icons.laptop_mac,
                      title: '本机摄像头',
                      subtitle: _isLocalCameraSupported
                          ? '使用当前设备的摄像头拍摄'
                          : '桌面平台暂不支持',
                      color: _isLocalCameraSupported ? Colors.teal : Colors.grey,
                      sourceType: SourceType.localCamera,
                      enabled: _isLocalCameraSupported,
                      onTap: () => _openLocalCamera(context),
                    ),
                    const SizedBox(height: 24),
                    _buildSourceCard(
                      context,
                      icon: Icons.phone_android,
                      title: '手机相机',
                      subtitle: '连接手机作为远程相机',
                      color: Colors.blue,
                      sourceType: SourceType.phoneCamera,
                      enabled: true,
                      onTap: () => _openPhoneCamera(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required SourceType sourceType,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Card(
      elevation: enabled ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: enabled ? onTap : () => _showUnsupportedDialog(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withOpacity(enabled ? 0.1 : 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: enabled ? color : Colors.grey[400],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: enabled ? null : Colors.grey[500],
                                  ),
                        ),
                        if (!enabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '暂不支持',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: enabled ? Colors.grey[600] : Colors.grey[400],
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled ? Colors.grey[400] : Colors.grey[300],
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnsupportedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('功能暂不可用'),
        content: const Text(
          '本机摄像头功能目前仅支持 Android 和 iOS 平台。\n\n'
          '在桌面平台上，请使用"手机相机"功能，连接您的手机进行拍摄。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _openLocalCamera(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const LocalCameraScreen(),
      ),
    );
  }

  void _openPhoneCamera(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DeviceConnectionScreen(),
      ),
    );
  }
}
