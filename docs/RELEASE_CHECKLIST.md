# 发布检查清单

本文档描述 **当前仓库实际使用的发布流程**。如文档与脚本行为冲突，请以 `scripts/` 和 `.github/workflows/` 为准。

## 一、发布前确认

- [ ] `VERSION.yaml` 中的 `client.version` / `server.version` 已更新
- [ ] 如有兼容性变更，已同步更新最小兼容版本配置
- [ ] 代码已提交并推送
- [ ] 本次发布对应的变更已验证
- [ ] 已准备好 GitHub 凭据（`gh auth login` 或 `GITHUB_TOKEN` / `GH_TOKEN`）

## 二、推荐发布流程

### 1. 检查版本

```bash
./scripts/version.sh get
```

如需更新版本：

```bash
./scripts/version.sh set client 1.0.8+13
./scripts/version.sh set server 1.0.8+13
./scripts/version.sh sync
```

> 建议把版本更新与代码改动一起提交，保证构建标签对应的 `VERSION.yaml` 可追溯。

### 2. 创建并推送构建标签

```bash
./scripts/create_build_tags.sh
```

说明：

- 脚本会从 `VERSION.yaml` 读取版本号。
- 生成的标签格式为 `build<x.y.z>`，例如 `build1.0.8`。
- 推送后会触发 `.github/workflows/build.yml`。

### 3. 等待构建完成

需要确认以下工作流已成功：

- `Build Client macOS`
- `Build Client Windows`
- `Build Server Android`
- `Increment Build Number`

构建完成后：

- GitHub Actions 会自动回写 `VERSION.yaml` 的 build number。
- 构建产物会被保存为后续 Release 所需的 artifacts。

### 4. 创建正式 Release

```bash
./scripts/create_release.sh 1.0.8
```

说明：

- 这里传入的是 **主版本号** `x.y.z`，不是 `x.y.z+build`。
- 脚本会检查对应的 `build<x.y.z>` 标签、构建结果和 artifacts。
- 校验通过后，脚本会触发 `.github/workflows/release.yml`。

### 5. 验证 GitHub Release

确认以下内容存在：

- [ ] `v1.0.8` 形式的正式 GitHub Release 已创建
- [ ] Release 中包含三个平台的发布文件
- [ ] `file_hashes.json` 已上传
- [ ] `UpdateConfig` Release 中已更新 `update_config_github.json`

## 三、发布后验证

### GitHub 更新源

- [ ] `update_config_github.json` 可访问
- [ ] 配置中的文件名、版本号、下载地址与本次发布一致
- [ ] 客户端可正常检测到更新

### Gitee 更新源（如果启用）

- [ ] `sync-to-gitee.yml` 已成功运行
- [ ] Gitee 对应版本 Release 已同步
- [ ] `config` Release 中的 `update_config_gitee.json` 已更新

## 四、失败排查顺序

### 构建失败

优先检查：

1. `.github/workflows/build.yml`
2. 三个平台复用工作流日志
3. `VERSION.yaml` 是否可被脚本正确读取

### `create_release.sh` 失败

优先检查：

1. 本地或远程是否存在 `build<x.y.z>` 标签
2. 对应构建工作流是否成功完成
3. 是否已配置 `gh` 登录或 `GITHUB_TOKEN`
4. GitHub artifacts 是否存在且名称正确

### 更新配置不正确

优先检查：

1. `.github/workflows/release.yml`
2. `scripts/generate_update_config.py`
3. `VERSION.yaml` 中记录的版本和更新 URL

## 五、关键事实速记

- **构建触发**：`build*` 标签
- **正式 Release 标签**：`v<x.y.z>`
- **GitHub 更新配置位置**：`UpdateConfig/update_config_github.json`
- **Gitee 更新配置位置**：`config/update_config_gitee.json`
- **版本事实来源**：`VERSION.yaml`
