# 版本管理指南

本项目采用 **`VERSION.yaml` 单一数据源** 管理版本号、最小兼容版本和更新配置地址。

## 一、版本号来源

根目录 `VERSION.yaml` 是唯一权威来源，内容包括：

- `client.version`
- `server.version`
- `compatibility.min_client_version`
- `compatibility.min_server_version`
- `update.github.url`
- `update.gitee.url`

示例结构：

```yaml
client:
  version: 1.0.8+13
server:
  version: 1.0.8+13
compatibility:
  min_client_version: 1.0.8
  min_server_version: 1.0.8
update:
  github:
    url: https://github.com/shichao402/HelloKnightRemoteCam/releases/download/UpdateConfig/update_config_github.json
  gitee:
    url: https://gitee.com/firoyang/HelloKnightRemoteCam/releases/download/config/update_config_gitee.json
```

## 二、版本号格式

使用 Flutter 常见格式：

```text
主版本.次版本.修订版本+构建号
```

例如：`1.0.8+13`

- `1.0.8`：主版本号，用于发布标签与版本比较
- `13`：构建号，用于区分同一主版本下的多次构建

## 三、管理命令

统一通过 `scripts/version.sh` 管理：

```bash
# 查看
./scripts/version.sh get
./scripts/version.sh get client
./scripts/version.sh get server

# 设置
./scripts/version.sh set client 1.0.8+13
./scripts/version.sh set server 1.0.8+13

# 递增
./scripts/version.sh bump client major
./scripts/version.sh bump client minor
./scripts/version.sh bump client patch
./scripts/version.sh bump client build

# 最小兼容版本
./scripts/version.sh set-min-version client 1.0.8
./scripts/version.sh set-min-version server 1.0.8

# 同步到 pubspec.yaml
./scripts/version.sh sync
./scripts/version.sh sync client
./scripts/version.sh sync server
```

## 四、版本同步规则

### 构建前同步

各平台构建脚本和工作流会从 `VERSION.yaml` 读取版本号，并同步到：

- `client/pubspec.yaml`
- `server/pubspec.yaml`
- 构建产物中的 `assets/VERSION.yaml` 或等效资源位置

### 运行时读取

应用运行时优先读取构建产物中的 `VERSION.yaml`；读取失败时，再回退到 `package_info_plus` 暴露的 `pubspec.yaml` 版本信息。

## 五、与构建 / 发布的关系

### 1. 构建阶段

执行：

```bash
./scripts/create_build_tags.sh
```

该脚本会：

- 从 `VERSION.yaml` 提取主版本号 `x.y.z`
- 创建 `build<x.y.z>` 标签
- 推送后触发 `.github/workflows/build.yml`

### 2. 构建完成后

`build.yml` 成功后会自动递增 `VERSION.yaml` 中的 build number，并回写到主分支。

这意味着：

- `build1.0.8` 对应的是一次“发布候选构建”
- 构建结果中的完整版本号（例如 `1.0.8+13`）仍然以该次构建携带的 `VERSION.yaml` 为准

### 3. 正式发布阶段

执行：

```bash
./scripts/create_release.sh 1.0.8
```

该脚本会基于 `build1.0.8` 对应的构建结果，触发 `release.yml` 创建：

- 正式 GitHub Release：`v1.0.8`
- 固定更新配置 Release：`UpdateConfig`

## 六、兼容性管理

`compatibility` 字段用于控制双向最低兼容版本：

- `min_client_version`：服务端要求客户端的最低版本
- `min_server_version`：客户端要求服务端的最低版本

典型场景：

- **只修 bug**：通常只需要 bump `patch` 或 `build`
- **新增向后兼容功能**：bump `minor`
- **破坏兼容**：bump `major`，并同步调整最小兼容版本

## 七、推荐工作流

### 日常开发

```bash
./scripts/version.sh get
```

### 准备发版

```bash
./scripts/version.sh set client 1.0.8+13
./scripts/version.sh set server 1.0.8+13
./scripts/version.sh sync
./scripts/create_build_tags.sh
./scripts/create_release.sh 1.0.8
```

## 八、不要这样做

- 不要只改 `client/pubspec.yaml` 或 `server/pubspec.yaml` 而不改 `VERSION.yaml`
- 不要把 `README.md` 当作版本事实来源
- 不要把 `raw.githubusercontent.com/.../update_config_github.json` 当成当前更新地址
- 不要假设“推 `v*` 标签就会自动完成整个发布流程”

## 九、相关文档

- [`VERSION_COPY_STRATEGY.md`](VERSION_COPY_STRATEGY.md)
- [`CI_CD_SETUP.md`](CI_CD_SETUP.md)
- [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
- [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
