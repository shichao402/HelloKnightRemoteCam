# VERSION.yaml 拷贝策略

本文档说明 `VERSION.yaml` 如何从仓库根目录进入构建产物，以及应用在运行时如何读取版本信息。

## 一、设计目标

### 1. 单一数据源

- 版本事实来源只有一个：根目录 `VERSION.yaml`
- 不在工作流、多个脚本、多个配置文件中重复维护版本号

### 2. 本地构建与 CI/CD 统一

- 本地脚本与 GitHub Actions 使用同一套版本提取逻辑
- 版本文件的拷贝由构建脚本与版本管理工具负责

### 3. 运行时优先读取版本文件

应用运行时采用以下优先级：

1. 构建产物中的 `VERSION.yaml`
2. `package_info_plus` 对应的 `pubspec.yaml` 版本信息
3. 默认回退值

## 二、当前落位策略

### 客户端（macOS / Windows）

客户端构建完成后，会把版本文件带入桌面产物，保证更新检查、版本显示与兼容性判断可以直接使用打包时的版本信息。

### 服务端（Android）

服务端构建前会把根目录 `VERSION.yaml` 同步到 `server/assets/VERSION.yaml`，再随 APK 一起打包。

## 三、CI/CD 中的版本读取

GitHub Actions 并不依赖 README 或手工输入版本号，而是通过：

- `scripts/lib/version_manager.py`
- `VERSION.yaml`
- 构建标签对应提交中的 `VERSION.yaml`

来提取真实版本信息。

特别是在 `release.yml` 中：

- 会先根据 `build<x.y.z>` 找到成功构建
- 再从该 build tag 对应提交里的 `VERSION.yaml` 提取完整版本号
- 最终生成 Release 资产文件名与更新配置

## 四、为什么不能只依赖 `pubspec.yaml`

`pubspec.yaml` 更适合作为 Flutter 打包元数据，而不是项目级版本事实来源，因为：

- 项目有 `client` / `server` 双端版本
- 还需要携带最小兼容版本和更新地址
- 发布流程需要同时消费多项版本元信息

因此当前策略是：

- `VERSION.yaml` 负责**管理**
- `pubspec.yaml` 负责**被同步与被 Flutter 读取**

## 五、推荐修改点

如果未来需要调整版本文件拷贝策略，请优先检查：

- `scripts/lib/version_manager.py`
- `client/scripts/build.sh`
- `server/scripts/build.sh`
- `.github/workflows/build-client-macos.yml`
- `.github/workflows/build-client-windows.yml`
- `.github/workflows/build-server-android.yml`
- `.github/workflows/release.yml`

## 六、验证清单

修改版本策略后，至少验证：

- [ ] 本地 `client` 构建后版本显示正确
- [ ] 本地 `server` 构建后可读取 `assets/VERSION.yaml`
- [ ] GitHub Actions 构建成功
- [ ] `release.yml` 可从 build tag 的 `VERSION.yaml` 正确生成 Release
- [ ] `update_config_github.json` / `update_config_gitee.json` 中版本号正确

## 七、相关文档

- [`VERSION_MANAGEMENT.md`](VERSION_MANAGEMENT.md)
- [`CI_CD_SETUP.md`](CI_CD_SETUP.md)
- [`AUTO_UPDATE.md`](AUTO_UPDATE.md)
