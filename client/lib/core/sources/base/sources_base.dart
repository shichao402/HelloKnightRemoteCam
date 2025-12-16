/// 数据源基础模块导出
library;

export 'source_types.dart';
export 'source_adapter.dart';
export 'capture_capability.dart';
// capture_controller 单独导出，避免与 camera 包冲突
// 使用时需要显式导入: import 'capture_controller.dart';
export 'capture_controller.dart' hide FlashMode;
export 'stream_capability.dart';
export 'file_source_capability.dart';
