import 'package:flutter/material.dart';
import 'package:mjpeg_stream/mjpeg_stream.dart';
import '../services/logger_service.dart';

/// 支持图像转置的预览Widget
/// 使用mjpeg_stream包显示MJPEG流，确保预览流始终以原始比例撑满预览窗口
/// 
/// 实现思路：
/// 1. 外层fit：根据容器和旋转后内容的宽高比匹配情况选择fit
/// 2. Transform.rotate：旋转整个内容
/// 3. 内层fit：根据旋转后内容方向选择fit
class TransformedPreviewWidget extends StatefulWidget {
  final String streamUrl;
  final int rotationAngle; // 旋转角度（0, 90, 180, 270）
  final int originalWidth; // 原始宽度
  final int originalHeight; // 原始高度
  final Function(int width, int height)? onSizeDetermined; // 转置后尺寸确定回调

  const TransformedPreviewWidget({
    Key? key,
    required this.streamUrl,
    required this.rotationAngle,
    required this.originalWidth,
    required this.originalHeight,
    this.onSizeDetermined,
  }) : super(key: key);

  @override
  State<TransformedPreviewWidget> createState() =>
      _TransformedPreviewWidgetState();
}

class _TransformedPreviewWidgetState extends State<TransformedPreviewWidget> {
  final ClientLoggerService _logger = ClientLoggerService();
  bool _sizeReported = false;

  // 计算转置后的尺寸
  (int width, int height) _getTransformedSize() {
    if (widget.rotationAngle == 90 || widget.rotationAngle == 270) {
      return (widget.originalHeight, widget.originalWidth);
    }
    return (widget.originalWidth, widget.originalHeight);
  }

  // 判断原始方向是横向还是纵向
  bool _isOriginalLandscape() {
    return widget.originalWidth > widget.originalHeight;
  }

  // 判断旋转后的方向是横向还是纵向
  bool _isRotatedLandscape() {
    final (width, height) = _getTransformedSize();
    return width > height;
  }

  @override
  void initState() {
    super.initState();
    _logger.log(
        '初始化转置预览: ${widget.originalWidth}x${widget.originalHeight}, 旋转角度=${widget.rotationAngle}°',
        tag: 'PREVIEW');
    _reportSize();
  }

  @override
  void didUpdateWidget(TransformedPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl ||
        oldWidget.rotationAngle != widget.rotationAngle ||
        oldWidget.originalWidth != widget.originalWidth ||
        oldWidget.originalHeight != widget.originalHeight) {
      _logger.log(
          '预览参数已更新，重新构造预览窗口: ${widget.originalWidth}x${widget.originalHeight}, 旋转角度=${widget.rotationAngle}°',
          tag: 'PREVIEW');
      _sizeReported = false;
      _reportSize();
    }
  }

  void _reportSize() {
    if (!_sizeReported) {
      final (width, height) = _getTransformedSize();
      widget.onSizeDetermined?.call(width, height);
      _sizeReported = true;
      _logger.log('转置后尺寸已确定: ${width}x${height}', tag: 'PREVIEW');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 判断方向
        final isOriginalLandscape = _isOriginalLandscape();
        final isRotatedLandscape = _isRotatedLandscape();
        final isContainerLandscape = constraints.maxWidth > constraints.maxHeight;
        
        // 计算宽高比
        final (rotatedWidth, rotatedHeight) = _getTransformedSize();
        final rotatedAspectRatio = rotatedWidth / rotatedHeight;
        final containerAspectRatio = constraints.maxWidth / constraints.maxHeight;
        
        // 计算预览流画面的实际尺寸（传递给MJPEGStreamScreen的尺寸）
        final streamWidth = widget.originalWidth.toDouble();
        final streamHeight = widget.originalHeight.toDouble();
        
        // 计算旋转后内容占用的边界框尺寸（Transform.rotate后占用的空间）
        // 当旋转90/270度时，边界框会交换宽高；当旋转0/180度时，边界框不变
        final (boundingWidth, boundingHeight) = (widget.rotationAngle == 90 || widget.rotationAngle == 270)
            ? (widget.originalHeight.toDouble(), widget.originalWidth.toDouble())
            : (widget.originalWidth.toDouble(), widget.originalHeight.toDouble());
        final boundingAspectRatio = boundingWidth / boundingHeight;
        
        // 手动计算缩放比例，确保旋转后的内容能够撑满容器
        // 使用contain逻辑：选择较小的缩放比例，确保内容完全显示不被裁剪
        final scaleX = constraints.maxWidth / boundingWidth;
        final scaleY = constraints.maxHeight / boundingHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY; // contain逻辑：选择较小的缩放，确保不裁剪
        
        // 计算缩放后的尺寸
        final scaledWidth = boundingWidth * scale;
        final scaledHeight = boundingHeight * scale;
        
        // 内层fit：根据旋转后内容方向选择
        // 如果旋转后是横向，使用cover；如果是纵向，使用contain（避免过度裁剪）
        final innerFit = isRotatedLandscape ? BoxFit.cover : BoxFit.contain;
        
        _logger.log(
            '构造预览窗口: 原始=${widget.originalWidth}x${widget.originalHeight} '
            '(${isOriginalLandscape ? "横向" : "纵向"}), '
            '旋转角度=${widget.rotationAngle}°, '
            '旋转后内容=${rotatedWidth}x${rotatedHeight} '
            '(${isRotatedLandscape ? "横向" : "纵向"}, 宽高比=${rotatedAspectRatio.toStringAsFixed(3)}), '
            '旋转后边界框=${boundingWidth.toInt()}x${boundingHeight.toInt()} '
            '(宽高比=${boundingAspectRatio.toStringAsFixed(3)}), '
            '容器=${constraints.maxWidth.toInt()}x${constraints.maxHeight.toInt()} '
            '(${isContainerLandscape ? "横向" : "纵向"}, 宽高比=${containerAspectRatio.toStringAsFixed(3)}), '
            '预览流画面=${streamWidth.toInt()}x${streamHeight.toInt()}, '
            '缩放比例=${scale.toStringAsFixed(3)} (scaleX=${scaleX.toStringAsFixed(3)}, scaleY=${scaleY.toStringAsFixed(3)}), '
            '缩放后=${scaledWidth.toInt()}x${scaledHeight.toInt()}, '
            '内层fit=${innerFit.toString()}',
            tag: 'PREVIEW');
        
        return SizedBox.expand(
          child: OverflowBox(
            // 允许内容超出容器，但不裁剪
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            alignment: Alignment.center,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: widget.rotationAngle * 3.14159 / 180,
                alignment: Alignment.center,
                child: FittedBox(
                  // 内层fit：根据旋转后的方向选择fit方式
                  fit: innerFit,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: widget.originalWidth.toDouble(),
                    height: widget.originalHeight.toDouble(),
                    child: MJPEGStreamScreen(
                      streamUrl: widget.streamUrl,
                      width: widget.originalWidth.toDouble(),
                      height: widget.originalHeight.toDouble(),
                      fit: BoxFit.fill, // 内部使用fill，由外层fit控制
                      showLiveIcon: false,
                      showLogs: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
