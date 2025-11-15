import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/device_config_service.dart';
import '../models/camera_settings.dart';
import '../models/camera_capabilities.dart';
import '../services/logger_service.dart';
import 'camera_capabilities_screen.dart';

class AdvancedCameraSettingsScreen extends StatefulWidget {
  final ApiService apiService;

  const AdvancedCameraSettingsScreen({Key? key, required this.apiService})
      : super(key: key);

  @override
  State<AdvancedCameraSettingsScreen> createState() =>
      _AdvancedCameraSettingsScreenState();
}

class _AdvancedCameraSettingsScreenState
    extends State<AdvancedCameraSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _deviceModel;

  // 基础设置
  String _videoQuality = 'ultra';
  String _photoQuality = 'ultra';
  bool _enableAudio = true;
  int _previewFps = 10;
  int _previewQuality = 70;

  // 高级设置
  Size? _selectedPhotoSize;
  Size? _selectedVideoSize;
  Size? _selectedPreviewSize;
  FpsRange? _selectedVideoFpsRange;

  // 可用选项
  List<Size> _availablePhotoSizes = [];
  List<Size> _availableVideoSizes = [];
  List<Size> _availablePreviewSizes = [];
  List<FpsRange> _availableFpsRanges = [];
  
  // 参数冲突信息
  List<String> _parameterConflicts = [];
  
  // 保存相机能力信息（用于根据分辨率过滤帧率）
  CameraCapabilities? _cameraCapabilities;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 获取设备信息
      final deviceInfoResult = await widget.apiService.getDeviceInfo();
      if (deviceInfoResult['success'] == true &&
          deviceInfoResult['deviceInfo'] != null) {
        final deviceInfo =
            deviceInfoResult['deviceInfo'] as Map<String, dynamic>;
        _deviceModel = deviceInfo['model'] as String?;
      }

      // 先获取相机能力信息（需要先知道可用选项）
      final capabilitiesResult =
          await widget.apiService.getAllCameraCapabilities();
      if (capabilitiesResult['success'] == true &&
          capabilitiesResult['capabilities'] != null) {
        final capabilitiesList = (capabilitiesResult['capabilities']
                as List<dynamic>)
            .map((e) => CameraCapabilities.fromJson(
                e as Map<String, dynamic>))
            .toList();

        if (capabilitiesList.isNotEmpty) {
          // 使用第一个相机（通常是后置相机）
          final mainCamera = capabilitiesList.first;
          setState(() {
            _cameraCapabilities = mainCamera;
            _availablePhotoSizes = mainCamera.photoSizes;
            _availableVideoSizes = mainCamera.videoSizes;
            _availablePreviewSizes = mainCamera.previewSizes;
            _availableFpsRanges = mainCamera.fpsRanges;
            _parameterConflicts = mainCamera.parameterConflicts;
          });
        }
      }

      // 获取当前设置（在获取能力信息之后，这样我们可以验证设置是否有效）
      final settingsResult = await widget.apiService.getSettings();
      if (settingsResult['success'] && settingsResult['settings'] != null) {
        final settings = settingsResult['settings'] as CameraSettings;
        setState(() {
          _videoQuality = settings.videoQuality;
          _photoQuality = settings.photoQuality;
          _enableAudio = settings.enableAudio;
          _previewFps = settings.previewFps;
          _previewQuality = settings.previewQuality;
          
          // 从可用列表中找到匹配的Size对象（确保对象引用一致）
          // 如果设置中的分辨率不在可用列表中，清除它（因为现在只显示真正支持的分辨率）
          if (settings.photoSize != null) {
            try {
              _selectedPhotoSize = _availablePhotoSizes.firstWhere(
                (size) => size.width == settings.photoSize!.width && size.height == settings.photoSize!.height,
              );
            } catch (e) {
              // 分辨率不在可用列表中，清除选择
              _selectedPhotoSize = null;
            }
          }
          if (settings.videoSize != null) {
            try {
              _selectedVideoSize = _availableVideoSizes.firstWhere(
                (size) => size.width == settings.videoSize!.width && size.height == settings.videoSize!.height,
              );
            } catch (e) {
              // 分辨率不在可用列表中，清除选择（因为现在只显示CamcorderProfile支持的分辨率）
              _selectedVideoSize = null;
            }
          }
          if (settings.previewSize != null) {
            try {
              _selectedPreviewSize = _availablePreviewSizes.firstWhere(
                (size) => size.width == settings.previewSize!.width && size.height == settings.previewSize!.height,
              );
            } catch (e) {
              // 分辨率不在可用列表中，清除选择
              _selectedPreviewSize = null;
            }
          }
          if (settings.videoFpsRange != null) {
            try {
              _selectedVideoFpsRange = _availableFpsRanges.firstWhere(
                (range) => range.min == settings.videoFpsRange!.min && range.max == settings.videoFpsRange!.max,
              );
            } catch (e) {
              // 帧率不在可用列表中，清除选择
              _selectedVideoFpsRange = null;
            }
          }
        });
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      final logger = ClientLoggerService();
      logger.logError('加载设置失败', error: e, stackTrace: stackTrace);
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
        previewFps: _previewFps,
        previewQuality: _previewQuality,
        photoSize: _selectedPhotoSize,
        videoSize: _selectedVideoSize,
        previewSize: _selectedPreviewSize,
        videoFpsRange: _selectedVideoFpsRange,
      );

      final result = await widget.apiService.updateSettings(newSettings);

      if (result['success']) {
        // 保存到设备配置
        if (_deviceModel != null && _deviceModel!.isNotEmpty) {
          final deviceConfigService = DeviceConfigService();
          await deviceConfigService.saveDeviceConfig(_deviceModel!, newSettings);
        }

        _showSuccess('设置已保存');
        Navigator.of(context).pop(true);
      } else {
        _showError(result['error'] ?? '保存失败');
      }
    } catch (e, stackTrace) {
      final logger = ClientLoggerService();
      logger.logError('保存设置失败', error: e, stackTrace: stackTrace);
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
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CameraCapabilitiesScreen(
                      apiService: widget.apiService,
                    ),
                  ),
                );
              },
              tooltip: '相机能力信息',
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: '刷新',
            ),
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
                      style: TextStyle(color: Colors.white, fontSize: 16),
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
                        onPressed: _loadData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : Container(
                  // 全屏布局，使用SafeArea确保内容不被系统UI遮挡
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      // 顶部信息栏（可选）
                      if (_deviceModel != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: Colors.blue[50],
                          child: Row(
                            children: [
                              Icon(Icons.phone_android,
                                  size: 16, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Text(
                                '设备: $_deviceModel',
                                style: TextStyle(
                                  color: Colors.blue[900],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // 参数冲突信息栏（如果有冲突）
                      if (_parameterConflicts.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          color: Colors.orange[50],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: 16, color: Colors.orange[700]),
                                  const SizedBox(width: 8),
                                  Text(
                                    '参数冲突警告',
                                    style: TextStyle(
                                      color: Colors.orange[900],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ..._parameterConflicts.map((conflict) {
                                return Padding(
                                  padding: const EdgeInsets.only(left: 24, bottom: 4),
                                  child: Text(
                                    '• $conflict',
                                    style: TextStyle(
                                      color: Colors.orange[900],
                                      fontSize: 11,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      // 主要内容区域（可滚动）
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                    // 相机信息入口
                    Card(
                      elevation: 2,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => CameraCapabilitiesScreen(
                                apiService: widget.apiService,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.info_outline,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '相机能力信息',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '查看设备支持的相机参数和分辨率',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // 基础设置
                    _buildSectionTitle('基础设置'),
                    _buildQualityCard('录像质量', _videoQuality, (value) {
                      setState(() {
                        _videoQuality = value!;
                      });
                    }),
                    const SizedBox(height: 16),
                    _buildQualityCard('拍照质量', _photoQuality, (value) {
                      setState(() {
                        _photoQuality = value!;
                      });
                    }),
                    const SizedBox(height: 16),
                    _buildAudioCard(),
                    const SizedBox(height: 16),
                    _buildPreviewFpsCard(),
                    const SizedBox(height: 16),
                    _buildPreviewQualityCard(),

                    const SizedBox(height: 32),

                    // 高级设置
                    _buildSectionTitle('高级设置（分辨率）'),
                    if (_availablePhotoSizes.isNotEmpty)
                      _buildSizeCard(
                        '照片分辨率',
                        _selectedPhotoSize,
                        _availablePhotoSizes,
                        (size) {
                          setState(() {
                            _selectedPhotoSize = size;
                          });
                        },
                      ),
                    if (_availablePhotoSizes.isNotEmpty)
                      const SizedBox(height: 16),
                    if (_availableVideoSizes.isNotEmpty)
                      _buildSizeCard(
                        '视频分辨率',
                        _selectedVideoSize,
                        _availableVideoSizes,
                        (size) {
                          setState(() {
                            _selectedVideoSize = size;
                          });
                        },
                      ),
                    if (_availableVideoSizes.isNotEmpty)
                      const SizedBox(height: 16),
                    if (_availablePreviewSizes.isNotEmpty)
                      _buildSizeCard(
                        '预览分辨率',
                        _selectedPreviewSize,
                        _availablePreviewSizes,
                        (size) {
                          setState(() {
                            _selectedPreviewSize = size;
                          });
                        },
                      ),
                    if (_availablePreviewSizes.isNotEmpty)
                      const SizedBox(height: 16),
                    if (_availableFpsRanges.isNotEmpty)
                      _buildFpsRangeCard(),

                    const SizedBox(height: 32),

                            // 说明
                            _buildInfoCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.grey[900], // 确保深色文字，与浅色背景对比
        ),
      ),
    );
  }

  Widget _buildQualityCard(
      String title, String value, ValueChanged<String?> onChanged) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900], // 确保深色文字，与浅色背景对比
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: value,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              style: TextStyle(fontSize: 16, color: Colors.grey[900]), // 确保深色文字
              items: [
                DropdownMenuItem(value: 'ultra', child: Text('超高 (Ultra)', style: TextStyle(color: Colors.grey[900]))),
                DropdownMenuItem(value: 'high', child: Text('高 (High)', style: TextStyle(color: Colors.grey[900]))),
                DropdownMenuItem(value: 'medium', child: Text('中 (Medium)', style: TextStyle(color: Colors.grey[900]))),
                DropdownMenuItem(value: 'low', child: Text('低 (Low)', style: TextStyle(color: Colors.grey[900]))),
              ],
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCard() {
    return Card(
      elevation: 2,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(
          '启用音频录制',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[900], // 确保深色文字
          ),
        ),
        subtitle: Text(
          '录像时录制音频',
          style: TextStyle(color: Colors.grey[700]), // 确保深色文字
        ),
        value: _enableAudio,
        onChanged: (value) {
          setState(() {
            _enableAudio = value;
          });
        },
      ),
    );
  }

  Widget _buildPreviewFpsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '预览帧率',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900], // 确保深色文字
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前: $_previewFps fps',
              style: TextStyle(fontSize: 16, color: Colors.grey[900]), // 确保深色文字
            ),
            const SizedBox(height: 16),
            Slider(
              value: _previewFps.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: '$_previewFps fps',
              onChanged: (value) {
                setState(() {
                  _previewFps = value.round();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewQualityCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '预览JPEG质量',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900], // 确保深色文字
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前: $_previewQuality%',
              style: TextStyle(fontSize: 16, color: Colors.grey[900]), // 确保深色文字
            ),
            const SizedBox(height: 16),
            Slider(
              value: _previewQuality.toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              label: '$_previewQuality%',
              onChanged: (value) {
                setState(() {
                  _previewQuality = value.round();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeCard(String title, Size? selectedSize,
      List<Size> availableSizes, ValueChanged<Size?> onChanged) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900], // 确保深色文字，与浅色背景对比
              ),
            ),
            const SizedBox(height: 8),
            Text(
              selectedSize != null
                  ? '当前: ${selectedSize.displayString} (${selectedSize.megapixels.toStringAsFixed(1)}MP)'
                  : '未选择（使用质量预设）',
              style: TextStyle(
                color: selectedSize != null ? Colors.grey[700] : Colors.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Size>(
              value: selectedSize != null
                  ? (availableSizes.any(
                      (size) => size.width == selectedSize!.width && size.height == selectedSize!.height
                    )
                      ? availableSizes.firstWhere(
                          (size) => size.width == selectedSize!.width && size.height == selectedSize!.height,
                        )
                      : null) // 如果选中的分辨率不在可用列表中，返回null
                  : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '使用质量预设',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              style: TextStyle(fontSize: 16, color: Colors.grey[900]), // 确保深色文字
              items: [
                DropdownMenuItem<Size>(
                  value: null,
                  child: Text('使用质量预设', style: TextStyle(color: Colors.grey[900])),
                ),
                ...availableSizes.map((size) {
                  return DropdownMenuItem<Size>(
                    value: size,
                    child: Text(
                        '${size.displayString} (${size.megapixels.toStringAsFixed(1)}MP)',
                        style: TextStyle(color: Colors.grey[900])),
                  );
                }),
              ],
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFpsRangeCard() {
    // 根据选中的分辨率，过滤出该分辨率支持的帧率
    List<FpsRange> compatibleFpsRanges = [];
    if (_selectedVideoSize != null && _cameraCapabilities != null) {
      // 找到选中的分辨率在能力信息中的对应项
      final videoSizeInfo = _cameraCapabilities!.videoSizes.firstWhere(
        (size) => size.width == _selectedVideoSize!.width && 
                  size.height == _selectedVideoSize!.height,
        orElse: () => _selectedVideoSize!,
      );
      
      // 如果该分辨率有supportedFps信息，只显示支持的帧率
      if (videoSizeInfo.supportedFps != null && videoSizeInfo.supportedFps!.isNotEmpty) {
        // 从_availableFpsRanges中过滤出支持的帧率
        compatibleFpsRanges = _availableFpsRanges.where((range) {
          // 检查帧率范围是否与支持的帧率有交集
          return videoSizeInfo.supportedFps!.any((fps) => 
            fps >= range.min && fps <= range.max
          );
        }).toList();
      } else {
        // 如果没有supportedFps信息，显示所有可用的帧率范围
        compatibleFpsRanges = _availableFpsRanges;
      }
    } else {
      // 如果没有选中分辨率，显示所有可用的帧率范围
      compatibleFpsRanges = _availableFpsRanges;
    }
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '视频帧率范围',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900], // 确保深色文字
              ),
            ),
            const SizedBox(height: 8),
            if (_selectedVideoSize != null && compatibleFpsRanges.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '警告：选中的分辨率 ${_selectedVideoSize!.displayString} 没有对应的帧率信息',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                  ),
                ),
              ),
            Text(
              _selectedVideoFpsRange != null
                  ? '当前: ${_selectedVideoFpsRange!.displayString}'
                  : '未选择（使用默认）',
              style: TextStyle(
                color: _selectedVideoFpsRange != null
                    ? Colors.grey[700]
                    : Colors.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<FpsRange>(
              value: _selectedVideoFpsRange != null
                  ? (compatibleFpsRanges.any(
                      (range) => range.min == _selectedVideoFpsRange!.min && range.max == _selectedVideoFpsRange!.max
                    )
                      ? compatibleFpsRanges.firstWhere(
                          (range) => range.min == _selectedVideoFpsRange!.min && range.max == _selectedVideoFpsRange!.max,
                        )
                      : null) // 如果选中的帧率不在兼容列表中，返回null
                  : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '使用默认',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              style: TextStyle(fontSize: 16, color: Colors.grey[900]), // 确保深色文字
              items: [
                DropdownMenuItem<FpsRange>(
                  value: null,
                  child: Text('使用默认', style: TextStyle(color: Colors.grey[900])),
                ),
                ...compatibleFpsRanges.map((range) {
                  return DropdownMenuItem<FpsRange>(
                    value: range,
                    child: Text(range.displayString, style: TextStyle(color: Colors.grey[900])),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedVideoFpsRange = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  '提示',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• 分辨率设置会覆盖质量预设\n'
              '• 选择"使用质量预设"将根据质量级别自动选择分辨率\n'
              '• 设置会自动保存到设备配置，下次连接时自动应用\n'
              '• 录像中无法更改设置',
              style: TextStyle(color: Colors.blue[900]),
            ),
          ],
        ),
      ),
    );
  }
}

