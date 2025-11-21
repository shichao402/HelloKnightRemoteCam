# 预览旋转和转置实现文档

## 概述

本文档描述了HelloKnightRemoteCam项目中预览画面的旋转和转置实现，包括方向锁定、手动旋转、自适应缩放等功能。

## 核心组件

### 1. TransformedPreviewWidget

**位置**: `client/lib/widgets/transformed_preview_widget.dart`

**职责**: 
- 显示MJPEG预览流
- 处理图像旋转和转置
- 自适应缩放以适配容器

**实现思路**:
1. 计算旋转后内容占用的边界框尺寸
2. 使用contain逻辑手动计算缩放比例（选择较小的缩放，确保不裁剪）
3. Transform.scale：应用缩放
4. Transform.rotate：旋转内容
5. FittedBox：内层fit根据旋转后内容方向选择

### 2. 方向管理

**位置**: `client/lib/screens/camera_control_screen.dart`

**功能**:
- **方向锁定**: 锁定/解锁设备方向跟随
- **手动旋转**: 在锁定状态下手动旋转预览（0°、90°、180°、270°）
- **自动适配**: 预览窗口自动适配，保持原始比例

## 技术实现

### 1. MJPEG流显示

使用 `mjpeg_stream` 包显示MJPEG流：

```dart
MJPEGStreamScreen(
  streamUrl: widget.streamUrl,
  width: widget.originalWidth.toDouble(),
  height: widget.originalHeight.toDouble(),
  fit: BoxFit.fill,
  showLiveIcon: false,
  showLogs: false,
)
```

### 2. 旋转和缩放计算

#### 2.1 边界框计算

当旋转90°或270°时，边界框会交换宽高：

```dart
final (boundingWidth, boundingHeight) = 
    (widget.rotationAngle == 90 || widget.rotationAngle == 270)
        ? (widget.originalHeight.toDouble(), widget.originalWidth.toDouble())
        : (widget.originalWidth.toDouble(), widget.originalHeight.toDouble());
```

#### 2.2 缩放比例计算

使用contain逻辑，选择较小的缩放比例，确保内容完全显示不被裁剪：

```dart
final scaleX = constraints.maxWidth / boundingWidth;
final scaleY = constraints.maxHeight / boundingHeight;
final scale = scaleX < scaleY ? scaleX : scaleY; // contain逻辑
```

#### 2.3 旋转和缩放应用

```dart
Transform.scale(
  scale: scale,
  alignment: Alignment.center,
  child: Transform.rotate(
    angle: widget.rotationAngle * 3.14159 / 180,
    alignment: Alignment.center,
    child: FittedBox(
      fit: innerFit,
      alignment: Alignment.center,
      child: SizedBox(
        width: widget.originalWidth.toDouble(),
        height: widget.originalHeight.toDouble(),
        child: MJPEGStreamScreen(...),
      ),
    ),
  ),
)
```

### 3. 方向锁定和旋转

#### 3.1 方向锁定状态

- **锁定状态**: 使用固定的旋转角度（`_lockedRotationAngle`）
- **解锁状态**: 自动跟随设备方向（从服务器获取传感器方向）

#### 3.2 旋转角度计算

```dart
int _calculatePreviewRotationAngle() {
  if (_orientationLocked) {
    // 锁定状态：使用手动设置的旋转角度
    return _lockedRotationAngle;
  } else {
    // 解锁状态：根据传感器方向和设备方向计算
    // 计算逻辑...
  }
}
```

#### 3.3 手动旋转

在锁定状态下，用户可以点击旋转按钮手动调整方向：

```dart
void _rotatePreview() {
  setState(() {
    _lockedRotationAngle = (_lockedRotationAngle + 90) % 360;
  });
  _updatePreviewRotation();
}
```

## 数据流

```
服务器端
  ↓ 传感器方向 (sensorOrientation)
  ↓ 设备方向 (deviceOrientation)
  ↓ WebSocket通知
客户端
  ↓ _deviceOrientationNotifier
  ↓ _sensorOrientation
  ↓ _calculatePreviewRotationAngle()
  ↓ _rotationAngleNotifier
  ↓ TransformedPreviewWidget
  ↓ 计算边界框和缩放
  ↓ Transform.scale + Transform.rotate
  ↓ MJPEGStreamScreen
  ↓ UI显示
```

## 预览尺寸管理

### 1. 预览尺寸获取

预览尺寸通过WebSocket通知获取：

```dart
void _updatePreviewSize(Map<String, dynamic>? previewSizeData) {
  final width = previewSizeData['width'] as int?;
  final height = previewSizeData['height'] as int?;
  // 更新 _previewSizeNotifier
}
```

### 2. 转置后尺寸计算

根据旋转角度计算转置后的尺寸：

```dart
(int width, int height) _getTransformedSize() {
  if (widget.rotationAngle == 90 || widget.rotationAngle == 270) {
    return (widget.originalHeight, widget.originalWidth);
  }
  return (widget.originalWidth, widget.originalHeight);
}
```

## 关键特性

### 1. 自适应缩放

- **contain逻辑**: 选择较小的缩放比例，确保内容完全显示
- **保持比例**: 预览画面保持原始宽高比
- **不裁剪**: 使用contain逻辑，不会裁剪画面内容

### 2. 方向适配

- **自动跟随**: 解锁状态下自动跟随设备方向
- **手动调整**: 锁定状态下可以手动旋转
- **实时更新**: 方向变化时实时更新预览

### 3. 窗口适配

- **动态调整**: 预览窗口可以手动调整宽度
- **自动适配**: 预览画面自动适配窗口大小
- **保持比例**: 始终保持原始宽高比

## 日志记录

预览相关的操作都会记录详细日志：

- 预览尺寸更新
- 旋转角度变化
- 缩放比例计算
- 容器尺寸变化

日志标签：`PREVIEW`

## 注意事项

1. **性能考虑**: 旋转和缩放计算在每次build时进行，但使用了LayoutBuilder优化
2. **内存管理**: MJPEG流使用mjpeg_stream包管理，自动处理内存释放
3. **网络稳定性**: 预览流支持自动重连，网络中断后会自动恢复
4. **方向同步**: 方向变化通过WebSocket实时同步，确保客户端和服务器一致

## 测试建议

1. **方向测试**: 测试锁定/解锁状态下的方向变化
2. **旋转测试**: 测试手动旋转功能（0°、90°、180°、270°）
3. **缩放测试**: 测试不同窗口大小下的预览适配
4. **网络测试**: 测试网络中断后的自动重连
5. **性能测试**: 测试长时间运行的内存使用情况

## 未来优化方向

1. **硬件加速**: 考虑使用GPU加速旋转和缩放
2. **缓存优化**: 优化预览帧的缓存策略
3. **自适应质量**: 根据网络状况自动调整预览质量
4. **多窗口支持**: 支持多个预览窗口同时显示

