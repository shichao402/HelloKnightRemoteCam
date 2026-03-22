# Gitee Release 同步配置

本项目当前使用 GitHub 作为主要构建与 Release 来源，Gitee 作为可选的同步分发源。

## 一、同步工作流

使用的工作流文件：

- `.github/workflows/sync-to-gitee.yml`

支持三种触发方式：

- GitHub Release 发布后自动触发
- 手动 `workflow_dispatch`
- 被其他 workflow 调用

## 二、同步内容

工作流会执行以下动作：

1. 获取要同步的 GitHub Release
2. 下载该 Release 的资产文件
3. 在 Gitee 创建 / 覆盖对应版本的 Release
4. 上传发布文件到 Gitee Release
5. 生成 `update_config_gitee.json`
6. 将更新配置上传到固定的 `config` Release

## 三、需要配置的 Secrets

在 GitHub 仓库设置中配置：

- `GITEE_TOKEN`
- `GITEE_REPO_OWNER`
- `GITEE_REPO_NAME`

### 含义

- **`GITEE_TOKEN`**：Gitee API 访问令牌
- **`GITEE_REPO_OWNER`**：Gitee 用户名或组织名
- **`GITEE_REPO_NAME`**：Gitee 仓库名

## 四、更新配置文件位置

Gitee 更新配置并不是放在仓库 raw 文件地址，而是固定放在：

```text
config/update_config_gitee.json
```

URL 形态：

```text
https://gitee.com/<owner>/<repo>/releases/download/config/update_config_gitee.json
```

## 五、手动触发方式

如果自动同步失败，或需要重新同步某个历史版本，可以手动运行 `sync-to-gitee.yml`：

- 输入版本号 `x.y.z`
- 工作流会自动补成 `v<x.y.z>` 或使用最新 Release

## 六、验证方式

### 同步成功后检查

- [ ] Gitee 对应版本 Release 已创建
- [ ] 资产文件数量与 GitHub Release 基本一致
- [ ] `config` Release 已存在
- [ ] `update_config_gitee.json` 已上传
- [ ] 配置中的下载地址指向 Gitee Release

## 七、常见失败点

### Secret 配置错误

表现：

- 无法访问 Gitee API
- 仓库不存在或权限不足

### Release 标签不一致

表现：

- GitHub Release 已存在，但 Gitee 查找不到对应标签

### 文件上传失败

表现：

- Release 创建成功，但部分大文件未上传完成

### 配置文件未更新

表现：

- `config` Release 存在，但 `update_config_gitee.json` 内容仍是旧版本

## 八、当前关键事实

- Gitee 同步是**后置同步流程**，不是主构建流程。
- 真实版本信息仍来自 build tag 对应的 `VERSION.yaml`。
- 固定配置 Release 标签是 `config`，而不是 `UpdateConfig`。

## 九、相关文档

- [`CI_CD_SETUP.md`](CI_CD_SETUP.md)
- [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
- [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
