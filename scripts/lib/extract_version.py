#!/usr/bin/env python3
"""
版本号提取脚本（用于 GitHub Actions）
此脚本是 version_manager.py 的简化包装器，专门用于 CI/CD 场景
"""

import sys
import os

# 添加脚本目录到路径
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

# 导入统一的版本管理模块
from version_manager import VersionManager

def main():
    """主函数"""
    if len(sys.argv) < 3:
        print("用法: extract_version.py <target> <action> [pubspec_path]", file=sys.stderr)
        print("  target: client 或 server", file=sys.stderr)
        print("  action: extract 或 sync", file=sys.stderr)
        print("  pubspec_path: (可选) pubspec.yaml 文件路径，sync 时必需", file=sys.stderr)
        sys.exit(1)
    
    target = sys.argv[1]  # client 或 server
    action = sys.argv[2]  # extract 或 sync
    
    if target not in ['client', 'server']:
        print(f"错误: 目标必须是 'client' 或 'server'", file=sys.stderr)
        sys.exit(1)
    
    if action not in ['extract', 'sync']:
        print(f"错误: 操作必须是 'extract' 或 'sync'", file=sys.stderr)
        sys.exit(1)
    
    try:
        manager = VersionManager()
        
        if action == 'extract':
            # 提取版本号（JSON 格式输出）
            import json
            version = manager.get_version(target)
            version_part, build_part = manager.parse_version(version)
            output = {
                'version': version_part,
                'build_number': build_part,
                'full_version': f"{version_part}+{build_part}",
                'tag_version': f'v{version_part}'
            }
            print(json.dumps(output, ensure_ascii=False))
        
        elif action == 'sync':
            # 同步版本号到 pubspec.yaml
            if len(sys.argv) < 4:
                print("错误: sync 操作需要指定 pubspec.yaml 路径", file=sys.stderr)
                sys.exit(1)
            
            pubspec_path = sys.argv[3]
            manager.sync_to_pubspec(target, pubspec_path)
            
            # 也输出版本信息（JSON 格式）
            import json
            version = manager.get_version(target)
            version_part, build_part = manager.parse_version(version)
            output = {
                'version': version_part,
                'build_number': build_part,
                'full_version': f"{version_part}+{build_part}",
                'tag_version': f'v{version_part}'
            }
            print(json.dumps(output, ensure_ascii=False))
    
    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
