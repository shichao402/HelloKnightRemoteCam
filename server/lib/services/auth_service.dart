import 'dart:io';
import 'dart:convert' show jsonEncode;
import 'package:shelf/shelf.dart';
import 'logger_service.dart';
import 'version_compatibility_service.dart';

/// 请求上下文
/// 包含客户端信息、认证信息等
class RequestContext {
  /// 客户端IP地址
  final String? clientIp;
  
  /// 客户端版本号
  final String? clientVersion;
  
  /// 用户ID（未来用于用户认证）
  final String? userId;
  
  /// 用户权限（未来用于权限控制）
  final List<String>? permissions;
  
  /// 是否已通过版本检查
  final bool versionChecked;
  
  /// 是否已通过用户认证
  final bool authenticated;
  
  /// 认证失败原因
  final String? authFailureReason;

  RequestContext({
    this.clientIp,
    this.clientVersion,
    this.userId,
    this.permissions,
    this.versionChecked = false,
    this.authenticated = false,
    this.authFailureReason,
  });

  /// 创建副本并更新字段
  RequestContext copyWith({
    String? clientIp,
    String? clientVersion,
    String? userId,
    List<String>? permissions,
    bool? versionChecked,
    bool? authenticated,
    String? authFailureReason,
  }) {
    return RequestContext(
      clientIp: clientIp ?? this.clientIp,
      clientVersion: clientVersion ?? this.clientVersion,
      userId: userId ?? this.userId,
      permissions: permissions ?? this.permissions,
      versionChecked: versionChecked ?? this.versionChecked,
      authenticated: authenticated ?? this.authenticated,
      authFailureReason: authFailureReason ?? this.authFailureReason,
    );
  }
}

/// 认证结果
class AuthResult {
  /// 是否通过认证
  final bool success;
  
  /// 失败原因
  final String? reason;
  
  /// 错误代码（用于客户端处理）
  final String? errorCode;
  
  /// 更新的请求上下文
  final RequestContext? context;

  AuthResult({
    required this.success,
    this.reason,
    this.errorCode,
    this.context,
  });

  /// 创建成功结果
  factory AuthResult.success({RequestContext? context}) {
    return AuthResult(
      success: true,
      context: context,
    );
  }

  /// 创建失败结果
  factory AuthResult.failure({
    required String reason,
    String? errorCode,
    RequestContext? context,
  }) {
    return AuthResult(
      success: false,
      reason: reason,
      errorCode: errorCode,
      context: context,
    );
  }
}

/// 统一的认证服务
/// 负责版本检查和用户认证
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final LoggerService _logger = LoggerService();
  final VersionCompatibilityService _versionCompatibilityService =
      VersionCompatibilityService();

  /// 从请求中提取客户端IP地址
  String? extractClientIp(Request request) {
    // 方法1: 从请求头获取（如果有代理）
    if (request.headers.containsKey('x-forwarded-for')) {
      final forwarded = request.headers['x-forwarded-for']!;
      // x-forwarded-for可能包含多个IP，取第一个
      final ip = forwarded.split(',').first.trim();
      if (ip.isNotEmpty && ip != 'unknown') {
        return ip;
      }
    }

    // 方法2: 从连接信息获取（直接连接）
    final connectionInfo =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    if (connectionInfo != null) {
      return connectionInfo.remoteAddress.address;
    }

    // 方法3: 从请求的IP头获取
    if (request.headers.containsKey('x-real-ip')) {
      final ip = request.headers['x-real-ip']!;
      if (ip.isNotEmpty && ip != 'unknown') {
        return ip;
      }
    }

    return null;
  }

  /// 从请求中提取客户端版本号
  /// 优先从URL查询参数获取，其次从请求头获取
  String? extractClientVersion(Request request) {
    // 优先从URL查询参数获取
    final queryVersion = request.url.queryParameters['clientVersion'];
    if (queryVersion != null && queryVersion.isNotEmpty) {
      return queryVersion;
    }

    // 其次从请求头获取
    final headerVersion = request.headers['x-client-version'];
    if (headerVersion != null && headerVersion.isNotEmpty) {
      return headerVersion;
    }

    return null;
  }

  /// 创建初始请求上下文
  RequestContext createInitialContext(Request request) {
    return RequestContext(
      clientIp: extractClientIp(request),
      clientVersion: extractClientVersion(request),
    );
  }

  /// 检查版本兼容性
  /// 返回认证结果，如果通过则更新上下文
  Future<AuthResult> checkVersion(RequestContext context) async {
    // 如果已经检查过版本，直接返回成功
    if (context.versionChecked) {
      return AuthResult.success(context: context);
    }

    final clientVersion = context.clientVersion;

    // 如果没有提供版本号，记录警告但允许访问（向后兼容）
    if (clientVersion == null || clientVersion.isEmpty) {
      _logger.log(
          '请求未提供客户端版本号，允许访问（向后兼容，路径: ${context.clientIp ?? "unknown"}）',
          tag: 'AUTH');
      return AuthResult.success(
        context: context.copyWith(versionChecked: true),
      );
    }

    // 检查版本兼容性
    try {
      final (isCompatible, reason) = await _versionCompatibilityService
          .checkClientVersion(clientVersion);

      if (!isCompatible) {
        _logger.log(
            '版本检查失败: $reason (客户端版本: $clientVersion)',
            tag: 'AUTH');
        return AuthResult.failure(
          reason: reason ?? '客户端版本不兼容',
          errorCode: 'VERSION_INCOMPATIBLE',
          context: context.copyWith(
            versionChecked: true,
            authFailureReason: reason,
          ),
        );
      }

      _logger.log('版本检查通过: $clientVersion', tag: 'AUTH');
      return AuthResult.success(
        context: context.copyWith(versionChecked: true),
      );
    } catch (e, stackTrace) {
      _logger.logError('版本检查异常', error: e, stackTrace: stackTrace);
      // 检查异常时，为了向后兼容，允许访问
      return AuthResult.success(
        context: context.copyWith(versionChecked: true),
      );
    }
  }

  /// 检查用户认证（预留接口）
  /// 未来实现用户认证逻辑
  Future<AuthResult> checkAuthentication(RequestContext context) async {
    // 如果已经认证过，直接返回成功
    if (context.authenticated) {
      return AuthResult.success(context: context);
    }

    // TODO: 实现用户认证逻辑
    // 例如：
    // 1. 从请求头获取token: request.headers['authorization']
    // 2. 验证token有效性
    // 3. 获取用户信息和权限
    // 4. 更新上下文

    // 当前默认允许访问（未启用用户认证）
    _logger.log('用户认证未启用，允许访问', tag: 'AUTH');
    return AuthResult.success(
      context: context.copyWith(authenticated: true),
    );
  }

  /// 综合认证检查（版本检查 + 用户认证）
  /// 按顺序执行：版本检查 -> 用户认证
  Future<AuthResult> authenticate(Request request) async {
    // 创建初始上下文
    final context = createInitialContext(request);

    // 步骤1: 版本检查
    final versionResult = await checkVersion(context);
    if (!versionResult.success) {
      return versionResult;
    }

    // 步骤2: 用户认证（使用更新后的上下文）
    final authResult = await checkAuthentication(versionResult.context!);
    if (!authResult.success) {
      return authResult;
    }

    // 所有检查通过
    return AuthResult.success(context: authResult.context);
  }

  /// 创建认证失败的HTTP响应
  Future<Response> createAuthFailureResponse(AuthResult result) async {
    final statusCode = result.errorCode == 'VERSION_INCOMPATIBLE' ? 403 : 401;
    
    // 构建响应体
    final responseBody = <String, dynamic>{
      'success': false,
      'error': result.reason ?? '认证失败',
      'errorCode': result.errorCode,
    };
    
    if (result.context?.clientVersion != null) {
      responseBody['clientVersion'] = result.context!.clientVersion;
    }
    
    // 如果是版本不兼容错误，需要异步获取最小版本要求
    if (result.errorCode == 'VERSION_INCOMPATIBLE') {
      try {
        final minVersion = await _versionCompatibilityService.getMinClientVersion();
        responseBody['minRequiredVersion'] = minVersion;
      } catch (e, stackTrace) {
        _logger.logError('获取最小客户端版本失败', error: e, stackTrace: stackTrace);
        // 如果获取失败，使用默认值
        responseBody['minRequiredVersion'] = '1.0.0';
      }
    }
    
    return Response(
      statusCode,
      body: jsonEncode(responseBody),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

