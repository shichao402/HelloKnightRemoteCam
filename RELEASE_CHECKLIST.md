# 发布检查清单（入口）

详细发布说明已经收敛到 [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)。

## 快速入口

- **详细步骤**：[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)
- **CI/CD 流程**：[`docs/CI_CD_SETUP.md`](docs/CI_CD_SETUP.md)
- **版本管理**：[`docs/VERSION_MANAGEMENT.md`](docs/VERSION_MANAGEMENT.md)

## 当前发布流程速记

1. 先确认 `VERSION.yaml`
2. 执行 `./scripts/create_build_tags.sh`
3. 等待 `build.yml` 构建完成
4. 执行 `./scripts/create_release.sh <x.y.z>`
5. 验证 GitHub Release 与 `UpdateConfig` Release

> 注意：当前仓库不是“直接推 `v*` 标签自动发版”的流程，而是“先 `build*` 构建，再手动触发 `release.yml` 创建正式 Release”。
