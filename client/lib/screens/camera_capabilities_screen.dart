import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/camera_capabilities.dart';
import '../services/logger_service.dart';

class CameraCapabilitiesScreen extends StatefulWidget {
  final ApiService apiService;

  const CameraCapabilitiesScreen({Key? key, required this.apiService})
      : super(key: key);

  @override
  State<CameraCapabilitiesScreen> createState() =>
      _CameraCapabilitiesScreenState();
}

class _CameraCapabilitiesScreenState extends State<CameraCapabilitiesScreen> {
  List<CameraCapabilities> _capabilities = [];
  bool _isLoading = false;
  String? _errorMessage;
  final ClientLoggerService _logger = ClientLoggerService();

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _logger.log('开始获取相机能力信息', tag: 'CAPABILITIES');
      final result = await widget.apiService.getAllCameraCapabilities();

      if (result['success'] == true && result['capabilities'] != null) {
        final capabilitiesList = (result['capabilities'] as List<dynamic>)
            .map((e) => CameraCapabilities.fromJson(
                e as Map<String, dynamic>))
            .toList();

        setState(() {
          _capabilities = capabilitiesList;
          _isLoading = false;
        });

        _logger.log('获取相机能力信息成功，找到${capabilitiesList.length}个相机',
            tag: 'CAPABILITIES');
      } else {
        setState(() {
          _errorMessage = result['error'] as String? ?? '获取失败';
          _isLoading = false;
        });
        _logger.logError('获取相机能力信息失败',
            error: Exception(_errorMessage));
      }
    } catch (e, stackTrace) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
      _logger.logError('获取相机能力信息异常', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相机能力信息'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCapabilities,
            tooltip: '刷新',
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
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        '获取失败',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadCapabilities,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _capabilities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            '未找到相机',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _loadCapabilities,
                            child: const Text('刷新'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _capabilities.length,
                      itemBuilder: (context, index) {
                        final caps = _capabilities[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ExpansionTile(
                            leading: Icon(
                              caps.lensDirection == 'back'
                                  ? Icons.camera_rear
                                  : Icons.camera_front,
                              color: Theme.of(context).primaryColor,
                            ),
                            title: Text(
                              '相机 ${caps.cameraId} (${caps.lensDirectionDisplayName})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '传感器方向: ${caps.sensorOrientation}°',
                            ),
                            children: [
                              _buildCapabilitySection(
                                '照片尺寸',
                                caps.photoSizes,
                                caps.maxPhotoSize,
                              ),
                              _buildCapabilitySection(
                                '视频尺寸',
                                caps.videoSizes,
                                caps.maxVideoSize,
                              ),
                              _buildCapabilitySection(
                                '预览尺寸',
                                caps.previewSizes,
                                caps.maxPreviewSize,
                              ),
                              _buildVideoQualities(caps),
                              _buildFpsRanges(caps),
                              _buildModes(caps),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildCapabilitySection(
    String title,
    List<Size> sizes,
    Size? maxSize,
  ) {
    if (sizes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (maxSize != null) ...[
                const Spacer(),
                Chip(
                  label: Text('最大: ${maxSize.displayString}'),
                  backgroundColor: Colors.blue[50],
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sizes.take(10).map((size) {
              return Chip(
                label: Text(
                  '${size.displayString}\n${size.megapixels.toStringAsFixed(1)}MP',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: size == maxSize
                    ? Colors.blue[100]
                    : Colors.grey[200],
              );
            }).toList(),
          ),
          if (sizes.length > 10)
            Text(
              '... 还有 ${sizes.length - 10} 个尺寸',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoQualities(CameraCapabilities caps) {
    if (caps.supportedVideoQualities.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支持的视频质量',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: caps.supportedVideoQualities.map((quality) {
              final qualityNames = {
                'ultra': '超高',
                'high': '高',
                'medium': '中',
                'low': '低',
              };
              return Chip(
                label: Text(qualityNames[quality] ?? quality),
                backgroundColor: Colors.green[100],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFpsRanges(CameraCapabilities caps) {
    if (caps.fpsRanges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支持的帧率范围',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: caps.fpsRanges.map((range) {
              return Chip(
                label: Text(range.displayString),
                backgroundColor: Colors.orange[100],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModes(CameraCapabilities caps) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支持的模式',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          if (caps.afModes.isNotEmpty)
            _buildModeRow('自动对焦 (AF)', caps.afModes.length),
          if (caps.aeModes.isNotEmpty)
            _buildModeRow('自动曝光 (AE)', caps.aeModes.length),
          if (caps.awbModes.isNotEmpty)
            _buildModeRow('自动白平衡 (AWB)', caps.awbModes.length),
        ],
      ),
    );
  }

  Widget _buildModeRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          Text(
            '$count 种模式',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

