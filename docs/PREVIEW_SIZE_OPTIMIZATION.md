# 预览尺寸数据流优化

## 问题分析

### 发现的问题

1. **数据不一致**：服务器端实际选择的预览尺寸是 1920x1080（16:9），但客户端收到的是 640x480（4:3）
2. **代码重复**：客户端在多处处理预览尺寸更新，代码重复且容易出错
3. **时序问题**：相机未初始化时返回默认值，可能导致数据不一致
4. **缺乏统一管理**：预览尺寸在多个接口返回，但处理逻辑分散

### 根本原因

1. **服务器端**：
   - `CameraService.getPreviewSize()` 在相机未初始化时返回默认值 640x480
   - WebSocket `connected` 事件和 `getStatus` 请求都调用同一个方法，但可能在不同时机调用
   - 如果相机未初始化，两个接口都返回默认值，但客户端只处理了 WebSocket `connected` 事件的预览尺寸

2. **客户端**：
   - WebSocket `connected` 事件处理预览尺寸（第363-376行）
   - `getStatus` 响应处理预览尺寸（第158-172行）
   - 两处代码重复，没有统一的方法
   - 如果 `getStatus` 在 `connected` 之后调用，可能会覆盖正确的预览尺寸

## 优化方案

### 1. 服务器端优化

#### 1.1 统一数据源
- `CameraService.getPreviewSize()` 现在返回 `Map<String, int>?`，如果相机未初始化返回 `null`
- 添加 `getPreviewSizeWithDefault()` 方法用于向后兼容
- 所有接口统一使用 `getPreviewSize() ?? {'width': 640, 'height': 480}` 确保一致性

#### 1.2 明确初始化状态
- 在返回预览尺寸时，日志中记录相机初始化状态
- 如果相机未初始化，使用默认值 640x480，但明确标识这是默认值

#### 1.3 接口一致性
- WebSocket `connected` 事件和 `getStatus` 请求都使用相同的逻辑获取预览尺寸
- 确保两个接口返回的数据一致

### 2. 客户端优化

#### 2.1 统一更新方法
- 提取 `_updatePreviewSize()` 方法，统一处理预览尺寸更新
- 所有预览尺寸更新都通过此方法处理，避免代码重复

#### 2.2 数据验证
- 检查预览尺寸数据是否完整（width 和 height 都不为 null）
- 检查预览尺寸是否变化，避免不必要的更新

#### 2.3 统一处理
- WebSocket `connected` 事件和 `getStatus` 响应都调用 `_updatePreviewSize()`
- 确保两个接口的预览尺寸更新逻辑一致

## 优化后的数据流

```
Android端 (Camera2Manager)
  ↓ actualPreviewWidth/actualPreviewHeight
NativeCameraService
  ↓ _previewWidth/_previewHeight (通过 _updatePreviewSize 更新)
CameraService
  ↓ getPreviewSize() (如果未初始化返回null)
HttpServerService
  ↓ getPreviewSize() ?? {'width': 640, 'height': 480}
  ├─ WebSocket connected 事件
  └─ getStatus 请求
客户端
  ↓ _updatePreviewSize() (统一处理)
_previewSizeNotifier (ValueNotifier)
  ↓
TransformedPreviewWidget
  ↓ 计算转置后尺寸
  ↓ 计算缩放比例（contain逻辑）
  ↓ Transform.scale + Transform.rotate
  ↓ MJPEGStreamScreen (mjpeg_stream包)
  ↓
UI更新
```

**注意**: 客户端现在使用 `mjpeg_stream` 包显示MJPEG流，并通过 `TransformedPreviewWidget` 处理旋转和缩放。详细实现请参考 [预览旋转实现文档](PREVIEW_ROTATION.md)。

## 关键改进点

1. **数据一致性**：所有接口使用相同的数据源和逻辑，确保返回一致的数据
2. **代码复用**：客户端统一使用 `_updatePreviewSize()` 方法，避免代码重复
3. **明确状态**：服务器端明确标识相机初始化状态，便于调试
4. **向后兼容**：保留 `getPreviewSizeWithDefault()` 方法，确保向后兼容

## 测试建议

1. 测试相机未初始化时，两个接口都返回默认值 640x480
2. 测试相机初始化后，两个接口都返回实际预览尺寸（如 1920x1080）
3. 测试客户端在两个接口返回不同值时，正确更新预览尺寸
4. 测试预览尺寸更新时，UI正确响应

## 注意事项

1. 如果相机未初始化，预览尺寸使用默认值 640x480，但这不是实际预览流的尺寸
2. 客户端应该监听相机初始化状态，在相机初始化完成后重新获取预览尺寸
3. 预览尺寸可能会在相机重新配置后改变，客户端应该监听状态变化

