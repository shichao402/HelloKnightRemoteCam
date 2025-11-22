/// 连接错误码
enum ConnectionErrorCode {
  /// 未知错误
  unknown,
  
  /// 网络错误（无法访问服务器）
  networkError,
  
  /// 版本不兼容（客户端版本过低）
  versionIncompatible,
  
  /// 服务器版本过低（服务器版本低于客户端要求）
  serverVersionTooLow,
  
  /// 认证失败（未来用于用户认证）
  authenticationFailed,
  
  /// 服务器拒绝连接（其他原因）
  connectionRefused,
  
  /// 连接超时
  connectionTimeout,
  
  /// 服务器内部错误
  serverError,
}

/// 连接错误信息
class ConnectionError {
  /// 错误码
  final ConnectionErrorCode code;
  
  /// 错误消息
  final String message;
  
  /// 详细错误信息（可选）
  final String? details;
  
  /// 最小要求版本（版本不兼容时）
  final String? minRequiredVersion;
  
  /// 客户端版本（版本不兼容时）
  final String? clientVersion;
  
  /// 服务器版本（版本不兼容时）
  final String? serverVersion;

  ConnectionError({
    required this.code,
    required this.message,
    this.details,
    this.minRequiredVersion,
    this.clientVersion,
    this.serverVersion,
  });

  /// 从错误码和消息创建错误
  factory ConnectionError.fromCode(
    ConnectionErrorCode code,
    String message, {
    String? details,
    String? minRequiredVersion,
    String? clientVersion,
    String? serverVersion,
  }) {
    return ConnectionError(
      code: code,
      message: message,
      details: details,
      minRequiredVersion: minRequiredVersion,
      clientVersion: clientVersion,
      serverVersion: serverVersion,
    );
  }

  /// 从服务器响应创建错误
  factory ConnectionError.fromServerResponse(Map<String, dynamic> response) {
    final errorCode = response['errorCode'] as String?;
    final errorMessage = response['error'] as String? ?? '连接失败';
    
    ConnectionErrorCode code;
    String message = errorMessage;
    String? minRequiredVersion;
    String? clientVersion;
    String? serverVersion;

    if (errorCode == 'VERSION_INCOMPATIBLE') {
      code = ConnectionErrorCode.versionIncompatible;
      minRequiredVersion = response['minRequiredVersion'] as String?;
      clientVersion = response['clientVersion'] as String?;
      
      if (minRequiredVersion != null && clientVersion != null) {
        message = '版本不兼容：客户端版本 $clientVersion 低于服务器要求的最小版本 $minRequiredVersion';
      } else {
        message = '版本不兼容：$errorMessage';
      }
    } else if (errorCode == 'AUTH_FAILED') {
      code = ConnectionErrorCode.authenticationFailed;
      message = '认证失败：$errorMessage';
    } else if (errorCode != null) {
      code = ConnectionErrorCode.connectionRefused;
      message = '连接被拒绝：$errorMessage';
    } else {
      code = ConnectionErrorCode.unknown;
      message = errorMessage;
    }

    return ConnectionError(
      code: code,
      message: message,
      details: response['details'] as String?,
      minRequiredVersion: minRequiredVersion,
      clientVersion: clientVersion,
      serverVersion: serverVersion,
    );
  }

  /// 从异常创建错误
  factory ConnectionError.fromException(dynamic exception) {
    final errorStr = exception.toString();
    
    if (errorStr.contains('403') || errorStr.contains('Forbidden')) {
      return ConnectionError(
        code: ConnectionErrorCode.versionIncompatible,
        message: '连接被拒绝：可能是版本不兼容',
        details: errorStr,
      );
    } else if (errorStr.contains('401') || errorStr.contains('Unauthorized')) {
      return ConnectionError(
        code: ConnectionErrorCode.authenticationFailed,
        message: '认证失败',
        details: errorStr,
      );
    } else if (errorStr.contains('timeout') || errorStr.contains('超时')) {
      return ConnectionError(
        code: ConnectionErrorCode.connectionTimeout,
        message: '连接超时：无法连接到服务器',
        details: errorStr,
      );
    } else if (errorStr.contains('refused') || errorStr.contains('拒绝')) {
      return ConnectionError(
        code: ConnectionErrorCode.connectionRefused,
        message: '连接被拒绝：服务器可能不可用',
        details: errorStr,
      );
    } else if (errorStr.contains('500') || errorStr.contains('Internal Server Error')) {
      // HTTP 500可能是服务器拒绝WebSocket升级（实际是403）
      // 检查是否包含版本相关信息
      if (errorStr.contains('version') || 
          errorStr.contains('版本') ||
          errorStr.contains('VERSION') ||
          errorStr.contains('was not upgraded to websocket')) {
        return ConnectionError(
          code: ConnectionErrorCode.versionIncompatible,
          message: '连接被拒绝：可能是版本不兼容',
          details: errorStr,
        );
      }
      return ConnectionError(
        code: ConnectionErrorCode.serverError,
        message: '服务器内部错误',
        details: errorStr,
      );
    } else {
      return ConnectionError(
        code: ConnectionErrorCode.networkError,
        message: '网络错误：无法访问服务器',
        details: errorStr,
      );
    }
  }

  /// 获取用户友好的错误消息
  String getUserFriendlyMessage() {
    switch (code) {
      case ConnectionErrorCode.versionIncompatible:
        if (minRequiredVersion != null && clientVersion != null) {
          return '版本不兼容\n\n客户端版本: $clientVersion\n要求最小版本: $minRequiredVersion\n\n请升级客户端后重试';
        }
        return message;
      case ConnectionErrorCode.serverVersionTooLow:
        if (serverVersion != null && minRequiredVersion != null) {
          return '服务器版本过低\n\n服务器版本: $serverVersion\n要求最小版本: $minRequiredVersion\n\n请升级服务器版本后重试';
        }
        return message;
      case ConnectionErrorCode.authenticationFailed:
        return '认证失败\n\n$message';
      case ConnectionErrorCode.networkError:
        return '无法访问服务器\n\n请检查：\n1. 服务器地址和端口是否正确\n2. 网络连接是否正常\n3. 服务器是否正在运行';
      case ConnectionErrorCode.connectionTimeout:
        return '连接超时\n\n请检查：\n1. 服务器地址和端口是否正确\n2. 网络连接是否正常\n3. 防火墙设置';
      case ConnectionErrorCode.connectionRefused:
        return '连接被拒绝\n\n$message';
      case ConnectionErrorCode.serverError:
        return '服务器错误\n\n服务器内部错误，请稍后重试';
      case ConnectionErrorCode.unknown:
        return message;
    }
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'code': code.name,
      'message': message,
      if (details != null) 'details': details,
      if (minRequiredVersion != null) 'minRequiredVersion': minRequiredVersion,
      if (clientVersion != null) 'clientVersion': clientVersion,
      if (serverVersion != null) 'serverVersion': serverVersion,
    };
  }
}

