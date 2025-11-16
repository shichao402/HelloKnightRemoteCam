# 认证架构设计文档

## 概述

本文档描述了HelloKnightRemoteCam项目的统一认证架构，支持版本检查和用户认证。

## 架构设计

### 1. 核心组件

#### 1.1 AuthService（认证服务）
- **位置**: `server/lib/services/auth_service.dart`
- **职责**: 
  - 统一的认证入口
  - 版本兼容性检查
  - 用户认证（预留接口）
  - 请求上下文管理

#### 1.2 RequestContext（请求上下文）
- **位置**: `server/lib/services/auth_service.dart`
- **职责**: 存储请求相关的认证信息
  - `clientIp`: 客户端IP地址
  - `clientVersion`: 客户端版本号
  - `userId`: 用户ID（未来用于用户认证）
  - `permissions`: 用户权限（未来用于权限控制）
  - `versionChecked`: 是否已通过版本检查
  - `authenticated`: 是否已通过用户认证

#### 1.3 AuthResult（认证结果）
- **位置**: `server/lib/services/auth_service.dart`
- **职责**: 封装认证结果
  - `success`: 是否通过认证
  - `reason`: 失败原因
  - `errorCode`: 错误代码（用于客户端处理）
  - `context`: 更新的请求上下文

### 2. 认证流程

#### 2.1 HTTP请求认证流程

```
HTTP请求
  ↓
CORS中间件
  ↓
日志中间件
  ↓
认证中间件 (authMiddleware)
  ├─→ 创建初始上下文 (提取IP、版本号)
  ├─→ 版本检查 (checkVersion)
  │   ├─→ 通过 → 继续
  │   └─→ 失败 → 返回403
  ├─→ 用户认证 (checkAuthentication) [预留]
  │   ├─→ 通过 → 继续
  │   └─→ 失败 → 返回401
  └─→ 将上下文存储到request.context
  ↓
路由处理
```

#### 2.2 WebSocket连接认证流程

```
WebSocket连接请求 (/ws)
  ↓
路由处理 (apiRouter.get('/ws'))
  ├─→ 执行统一认证 (authenticate)
  │   ├─→ 版本检查
  │   └─→ 用户认证 [预留]
  ├─→ 认证失败 → 返回HTTP 403/401
  └─→ 认证成功 → 建立WebSocket连接
```

#### 2.3 预览流认证流程

```
预览流请求 (/preview/stream)
  ↓
路由处理 (apiRouter.get('/preview/stream'))
  ├─→ 执行统一认证 (authenticate)
  │   ├─→ 版本检查
  │   └─→ 用户认证 [预留]
  ├─→ 认证失败 → 返回HTTP 403/401
  └─→ 认证成功 → 建立预览流连接
```

### 3. 版本检查

#### 3.1 版本号提取
- **优先级1**: URL查询参数 `?clientVersion=1.0.0`
- **优先级2**: HTTP请求头 `X-Client-Version: 1.0.0`

#### 3.2 版本检查逻辑
1. 如果未提供版本号：记录警告，允许访问（向后兼容）
2. 如果提供版本号：检查是否满足最小版本要求
   - 满足 → 通过
   - 不满足 → 返回403，错误代码 `VERSION_INCOMPATIBLE`

### 4. 用户认证（预留接口）

#### 4.1 当前状态
- 用户认证接口已预留，默认允许访问
- 未来可以实现：
  - Token验证
  - 用户权限检查
  - 会话管理

#### 4.2 实现示例（未来）

```dart
Future<AuthResult> checkAuthentication(RequestContext context) async {
  // 1. 从请求头获取token
  final token = request.headers['authorization'];
  
  // 2. 验证token
  final user = await tokenService.validateToken(token);
  if (user == null) {
    return AuthResult.failure(
      reason: '无效的认证token',
      errorCode: 'AUTH_FAILED',
    );
  }
  
  // 3. 获取用户权限
  final permissions = await userService.getPermissions(user.id);
  
  // 4. 更新上下文
  return AuthResult.success(
    context: context.copyWith(
      userId: user.id,
      permissions: permissions,
      authenticated: true,
    ),
  );
}
```

### 5. 错误响应

#### 5.1 版本不兼容
```json
{
  "success": false,
  "error": "客户端版本不兼容",
  "errorCode": "VERSION_INCOMPATIBLE",
  "clientVersion": "1.0.0",
  "minRequiredVersion": "1.0.1"
}
```
- HTTP状态码: 403 Forbidden

#### 5.2 认证失败（未来）
```json
{
  "success": false,
  "error": "无效的认证token",
  "errorCode": "AUTH_FAILED"
}
```
- HTTP状态码: 401 Unauthorized

### 6. 客户端集成

#### 6.1 WebSocket连接
```dart
final uri = Uri.parse('$wsUrl/ws').replace(queryParameters: {
  'clientVersion': clientVersion,
});
```

#### 6.2 HTTP请求
```dart
request.headers.add('X-Client-Version', clientVersion);
// 或
final url = '$baseUrl/endpoint?clientVersion=$clientVersion';
```

#### 6.3 预览流
```dart
final url = '$baseUrl/preview/stream?clientVersion=$clientVersion';
```

### 7. 扩展性

#### 7.1 添加新的认证步骤
在 `AuthService.authenticate()` 中添加新的检查步骤：

```dart
Future<AuthResult> authenticate(Request request) async {
  final context = createInitialContext(request);
  
  // 步骤1: 版本检查
  final versionResult = await checkVersion(context);
  if (!versionResult.success) return versionResult;
  
  // 步骤2: 用户认证
  final authResult = await checkAuthentication(versionResult.context!);
  if (!authResult.success) return authResult;
  
  // 步骤3: 新的检查（例如：IP白名单）
  final ipResult = await checkIpWhitelist(authResult.context!);
  if (!ipResult.success) return ipResult;
  
  return AuthResult.success(context: ipResult.context);
}
```

#### 7.2 添加权限检查
在路由处理中使用上下文中的权限信息：

```dart
final context = request.context['auth.context'] as RequestContext?;
if (context?.permissions?.contains('camera.control') != true) {
  return Response.forbidden(json.encode({
    'success': false,
    'error': '权限不足',
  }));
}
```

## 总结

统一认证架构提供了：
1. ✅ **版本检查**: 已实现并投入使用
2. 🔄 **用户认证**: 接口已预留，待实现
3. 🔄 **权限控制**: 接口已预留，待实现
4. ✅ **统一错误处理**: 已实现
5. ✅ **向后兼容**: 未提供版本号时允许访问
6. ✅ **可扩展性**: 易于添加新的认证步骤

## 未来改进

1. **用户认证实现**
   - Token生成和验证
   - 用户会话管理
   - 密码加密存储

2. **权限系统**
   - 基于角色的访问控制（RBAC）
   - 细粒度权限控制
   - 权限缓存

3. **安全增强**
   - IP白名单/黑名单
   - 请求频率限制
   - 异常检测和防护

