import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/camera_settings.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService apiService;

  const SettingsScreen({Key? key, required this.apiService}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  CameraSettings? _currentSettings;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  String _videoQuality = 'ultra';
  String _photoQuality = 'ultra';
  bool _enableAudio = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.apiService.getSettings();
      
      if (result['success'] && result['settings'] != null) {
        final settings = result['settings'] as CameraSettings;
        setState(() {
          _currentSettings = settings;
          _videoQuality = settings.videoQuality;
          _photoQuality = settings.photoQuality;
          _enableAudio = settings.enableAudio;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result['error'] ?? '加载设置失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '加载设置失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    // 检查设置状态
    final statusResult = await widget.apiService.getSettingsStatus();
    if (statusResult['success'] && statusResult['locked'] == true) {
      _showError('当前状态不允许更改设置（可能正在录像中）');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final newSettings = CameraSettings(
        videoQuality: _videoQuality,
        photoQuality: _photoQuality,
        enableAudio: _enableAudio,
        previewFps: _currentSettings?.previewFps ?? 10,
        previewQuality: _currentSettings?.previewQuality ?? 70,
      );

      final result = await widget.apiService.updateSettings(newSettings);

      if (result['success']) {
        _showSuccess('设置已保存');
        Navigator.of(context).pop(true); // 返回true表示设置已更新
      } else {
        _showError(result['error'] ?? '保存失败');
      }
    } catch (e) {
      _showError('保存失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相机设置'),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _saveSettings,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSettings,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 录像质量
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '录像质量',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '更改设置需要重新初始化相机，录像中无法更改',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildQualityDropdown(
                              value: _videoQuality,
                              onChanged: (value) {
                                setState(() {
                                  _videoQuality = value!;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 拍照质量
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '拍照质量',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildQualityDropdown(
                              value: _photoQuality,
                              onChanged: (value) {
                                setState(() {
                                  _photoQuality = value!;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 音频设置
                    Card(
                      child: SwitchListTile(
                        title: const Text(
                          '启用音频录制',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text('录像时录制音频'),
                        value: _enableAudio,
                        onChanged: (value) {
                          setState(() {
                            _enableAudio = value;
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 说明文本
                    const Card(
                      color: Colors.blue,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  '提示',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              '• 超高质量提供最佳画质但占用更多存储空间\n'
                              '• 高质量是推荐的平衡选项\n'
                              '• 中等和低质量适用于节省存储空间的场景\n'
                              '• 录像中无法更改质量设置',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildQualityDropdown({
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'ultra', child: Text('超高 (Ultra)')),
        DropdownMenuItem(value: 'high', child: Text('高 (High)')),
        DropdownMenuItem(value: 'medium', child: Text('中 (Medium)')),
        DropdownMenuItem(value: 'low', child: Text('低 (Low)')),
      ],
      onChanged: onChanged,
    );
  }
}

