# 自动更新功能文档

本文档说明项目当前的自动更新机制，包括更新配置文件的生成方式、发布位置和客户端消费方式。

## 一、总体流程

```text
构建成功
    ↓
release.yml 生成 update_config_github.json
    ↓
上传到固定的 UpdateConfig Release
    ↓
客户端读取 updateCheckUrl
    ↓
展示可更新版本与下载入口
```

如果启用了 Gitee 同步，则还会额外生成：

```text
sync-to-gitee.yml
    ↓
生成 update_config_gitee.json
    ↓
上传到固定的 config Release
```

## 二、更新配置文件位置

### GitHub

当前 GitHub 更新配置文件位于固定 Release：

```text
UpdateConfig/update_config_github.json
```

对应 URL 形态：

```text
https://github.com/<owner>/<repo>/releases/download/UpdateConfig/update_config_github.json
```

### Gitee

当前 Gitee 更新配置文件位于固定 Release：

```text
config/update_config_gitee.json
```

对应 URL 形态：

```text
https://gitee.com/<owner>/<repo>/releases/download/config/update_config_gitee.json
```

## 三、配置文件内容

更新配置至少包含：

- 客户端版本号
- 服务端版本号
- 各平台下载地址
- 文件名
- 文件哈希
- `updateCheckUrl`
- 更新时间

生成逻辑统一由：

- `scripts/generate_update_config.py`

负责。

## 四、下载文件命名

当前发布文件以 zip 为主：

- macOS：`HelloKnightRCC_macos_*.zip`
- Windows：`HelloKnightRCC_windows_*.zip`
- Android：`helloknightrcc_server_android_*.zip`

其中：

- macOS zip 内包含 dmg
- Windows zip 内包含 exe
- Android zip 内包含 apk

### 为什么文件名里会出现 `build`

部分发布文件名会把版本中的 `+` 转为 `build`，这是为了避免 URL 与文件系统场景下对特殊字符的处理差异。例如：

```text
1.0.8+13 -> 1.0.8build13
```

这不影响版本比较；版本字段仍保留标准的 `x.y.z+build` 形式。

## 五、客户端如何消费更新配置

客户端通过更新检查 URL 读取 JSON 配置，然后：

1. 读取本地当前版本
2. 与配置中的版本号比较
3. 如果发现更高版本，展示更新提示
4. 使用配置中的下载地址和文件哈希执行下载与校验

## 六、与 `VERSION.yaml` 的关系

`VERSION.yaml` 中保存了当前默认更新地址：

- `update.github.url`
- `update.gitee.url`

这两个地址应与发布工作流实际生成的位置保持一致。

## 七、当前已淘汰的旧路径

以下路径不应再作为当前 GitHub 更新配置地址使用：

```text
https://raw.githubusercontent.com/<owner>/<repo>/main/update_config_github.json
```

当前正确位置是固定的 `UpdateConfig` Release。

## 八、排查建议

### 更新检查失败

优先检查：

1. `VERSION.yaml` 中的更新 URL 是否正确
2. `UpdateConfig` / `config` Release 是否存在
3. 配置文件是否是有效 JSON
4. 客户端当前网络是否可访问对应下载源

### 下载成功但安装包不对

优先检查：

1. `release.yml` 生成的文件名是否正确
2. `generate_update_config.py` 写入的下载地址是否正确
3. Release 中实际上传的 zip 文件是否和配置一致

## 九、相关文档

- [`CI_CD_SETUP.md`](CI_CD_SETUP.md)
- [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
- [`GITEE_SYNC_SETUP.md`](GITEE_SYNC_SETUP.md)
