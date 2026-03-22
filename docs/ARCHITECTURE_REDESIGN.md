# 架构改造方案：作业管理 + 拍摄一体化平台

## 背景

将本项目从"纯远程拍摄工具"升级为"作业管理 + 拍摄一体化平台"。核心诉求：

1. 家长在企业微信群收到老师发的作业 → 自动解析为结构化任务
2. 通过 PC 客户端拍摄并关联到对应任务
3. 拍摄完成后自动整理结果，通过企业微信 Bot 批量发送/通知

## 架构总览

```
企业微信群
    ↕ 长连接 (OpenClaw)
┌──────────────────────────────────────────────────────┐
│  WeCom Agent（TypeScript，独立进程）                    │
│  • 企业微信 Bot 长连接                                 │
│  • LLM 解析消息 → 结构化作业                           │
│  • 通过 MCP 调 Core Service                           │
│  • 将任务状态变更转发为群消息                            │
└─────────────┬────────────────────────────────────────┘
              │ MCP (HTTP/SSE)
              ↓
┌──────────────────────────────────────────────────────┐
│  Core Service（独立进程，24h 常驻，家庭服务器）           │
│  ┌─ MCP Server ─────────────────────────────────┐    │
│  │  供 Agent / Claude Desktop / 其他 AI 工具调用  │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ REST API ───────────────────────────────────┐    │
│  │  供 Flutter 客户端精确调用                      │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ 事件推送 (WebSocket/SSE) ───────────────────┐    │
│  │  任务变更实时通知 → Flutter 客户端              │    │
│  └──────────────────────────────────────────────┘    │
│  • 任务 CRUD + 生命周期管理                           │
│  • 媒体-任务关联                                      │
│  • 持久化（SQLite）                                   │
│  职责：数据权威                                        │
└──────────────────────────────────────────────────────┘
              ↑ REST API + 事件推送
┌──────────────────────────────────────────────────────┐
│  Flutter 客户端（PC，按需启动）                         │
│  • 任务列表/详情 UI（读写 Core REST API）               │
│  • 拍摄控制（← → 手机）                                │
│  • 拍摄产物关联任务                                    │
│  • 本地媒体库（已有）                                   │
│  职责：UI + 拍摄                                       │
└─────────────┬────────────────────────────────────────┘
              │ WebSocket（已有）
              ↓
┌──────────────────────────────────────────────────────┐
│  手机服务端（不变）                                     │
└──────────────────────────────────────────────────────┘
```

## 架构决策

### 四个进程

| 进程 | 技术栈 | 运行方式 | 职责 |
|------|--------|---------|------|
| **Core Service** | 强类型语言（待定，倾向 TS） | 家庭服务器 24h 常驻 | 数据权威，暴露 REST API + MCP Server |
| **WeCom Agent** | TypeScript | 家庭服务器 24h 常驻 | 企业微信长连接(OpenClaw) + LLM 解析，通过 MCP 调 Core |
| **Flutter 客户端** | Dart/Flutter | PC 按需启动 | UI + 拍摄控制，通过 REST API 调 Core |
| **手机服务端** | Dart/Flutter | 拍摄时启动 | 纯拍摄服务（不变） |

### 通信设计

| 通信路径 | 协议 | 原因 |
|---------|------|------|
| Core ↔ Agent | MCP (HTTP/SSE) | LLM 需要理解工具语义 |
| Core ↔ Flutter | REST API + 事件推送 | 程序间精确对接，无需 LLM 参与 |
| Flutter ↔ 手机 | WebSocket + HTTP | 已有，不变 |

### 关键设计原则

1. **Core Service 是唯一数据权威** — 所有任务数据存在 Core Service 的 SQLite 中，PC 端和 Agent 都是消费者
2. **Agent 无状态** — Agent 挂了重启不丢数据，所有状态都在 Core Service
3. **MCP 只用于 AI 接口** — MCP 的价值在于让 LLM 能理解和调用工具；程序间精确调用使用 REST API
4. **Core Service 和 Agent 独立部署** — 虽然可以合为一个进程，但保持独立更清晰，职责单一

## 仓库结构（改造后）

```
HelloKnightRemoteCam/
├── client/              # Flutter 桌面客户端（已有，增强）
├── server/              # Android 手机服务端（已有，不变）
├── shared/              # Dart 共享层（已有，不变）
├── core/                # Core Service（新增）
│   ├── src/
│   │   ├── models/      # 任务、媒体关联等数据模型
│   │   ├── storage/     # SQLite 持久化层
│   │   ├── api/         # REST API 路由
│   │   ├── mcp/         # MCP Server 实现
│   │   ├── events/      # 事件推送（WebSocket/SSE）
│   │   └── main.ts      # 入口
│   ├── package.json
│   └── tsconfig.json
├── agent/               # WeCom Agent（新增）
│   ├── src/
│   │   ├── wecom/       # OpenClaw 长连接
│   │   ├── llm/         # LLM 调用 + 消息解析
│   │   ├── mcp-client/  # MCP Client（调 Core）
│   │   └── main.ts      # 入口
│   ├── package.json
│   └── tsconfig.json
├── docs/                # 文档（已有）
├── scripts/             # 脚本（已有）
├── assets/              # 资源文件（已有）
├── VERSION.yaml
├── PROJECT_OVERVIEW.md
└── README.md
```

## 核心数据模型

### Task（任务）

```typescript
interface Task {
  id: string;                    // UUID
  title: string;                 // 作业标题
  description: string;           // 作业详细描述
  status: 'pending' | 'in_progress' | 'completed' | 'returned';
  source: {                      // 来源信息
    channel: string;             // 来源渠道标识
    messageId?: string;          // 原始消息 ID
    rawContent?: string;         // 原始消息内容
  };
  attachments: Attachment[];     // 作业要求附件（老师发的图/文件）
  submissions: Submission[];     // 作业提交物（学生拍的照片/视频）
  dueDate?: string;              // 截止时间
  createdAt: string;
  updatedAt: string;
  completedAt?: string;
}
```

### Attachment（附件 — 老师发的作业要求材料）

```typescript
interface Attachment {
  id: string;
  taskId: string;
  type: 'image' | 'video' | 'file' | 'text';
  url?: string;                  // 原始 URL
  localPath?: string;            // 本地缓存路径
  description?: string;
}
```

### Submission（提交物 — 学生完成的拍摄产物）

```typescript
interface Submission {
  id: string;
  taskId: string;
  mediaId?: string;              // 关联 Flutter 媒体库的 media ID
  type: 'photo' | 'video' | 'file';
  localPath: string;
  thumbnailPath?: string;
  note?: string;                 // 学生备注
  createdAt: string;
}
```

## REST API 设计

```
GET    /api/tasks                       # 任务列表（支持 ?status= 筛选）
GET    /api/tasks/:id                   # 任务详情
POST   /api/tasks                       # 创建任务
PATCH  /api/tasks/:id                   # 更新任务（状态、内容）
DELETE /api/tasks/:id                   # 删除任务

POST   /api/tasks/:id/submissions       # 添加提交物
DELETE /api/tasks/:id/submissions/:sid  # 删除提交物

GET    /api/events                      # SSE 事件流（任务变更推送）
```

## MCP Server 工具定义

```
MCP Tools:
  - create_task(title, description, attachments, dueDate)
  - list_tasks(status?, keyword?)
  - get_task(id)
  - update_task(id, status?, title?, description?)
  - add_submission(taskId, filePath, type, note?)
  - notify_completion(taskId)        # 触发完成通知
  - get_task_summary(taskId)         # 获取任务摘要（供 Bot 发消息）
  - batch_export(taskIds)            # 批量整理作业结果
```

## 开发阶段

### Phase 1：Core Service（地基）

**目标**：搭建数据权威服务，暴露 REST API

- 初始化项目骨架（TypeScript + SQLite）
- 实现任务数据模型 + CRUD
- 实现 REST API
- 实现 SSE 事件推送
- 部署脚本（家庭服务器 systemd / pm2）

### Phase 2：Flutter 端任务模块

**目标**：客户端 UI 对接 Core API，拍摄产物关联任务

- 新增 `client/lib/core/tasks/` 模块（service + repository + models）
- 新增任务列表页、任务详情页
- 拍摄完成后支持选择关联任务
- 首页重构：任务入口从禁用变为可用，成为主要入口

### Phase 3：Core Service MCP Server 层

**目标**：为 LLM Agent 暴露 MCP 工具

- 实现 MCP Server（基于 `@modelcontextprotocol/sdk`）
- 注册所有 MCP 工具
- 测试 MCP 调用流程

### Phase 4：WeCom Agent + MCP 集成

**目标**：企业微信群 ↔ Core Service 打通

- OpenClaw 长连接接入
- 消息接收 → LLM 解析 → MCP 调用 Core 创建任务
- 监听任务完成事件 → 发送群通知
- 家长批阅指令解析（"通过 #T001"、"打回 #T001 重做口算"）
- 批量整理 → 发送作业结果供家长转发
