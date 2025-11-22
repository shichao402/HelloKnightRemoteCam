# Scripts Library

此目录包含内部使用的脚本和模块，不应直接调用。

## 文件说明

- `version_manager.py` - 版本管理核心模块，所有版本号读写操作都通过此模块完成
- `extract_version.py` - CI/CD 使用的版本号提取脚本（已统一到 version_manager.py）

## 使用方式

这些模块应该通过外层的用户接口脚本调用：
- `../version.sh` - 用户命令行接口
- `../create_release.sh` - 创建 Release 脚本

或者通过构建脚本调用：
- `../../client/scripts/build.sh`
- `../../server/scripts/build.sh`

## 架构说明

```
scripts/
├── version.sh              # 用户命令行接口（外层）
├── create_release.sh       # 用户创建 Release 脚本（外层）
├── collect_all_logs.sh     # 用户日志收集脚本（外层）
└── lib/                    # 内部实现（内层）
    ├── version_manager.py  # 版本管理核心模块
    └── extract_version.py  # CI/CD 版本提取脚本
```

