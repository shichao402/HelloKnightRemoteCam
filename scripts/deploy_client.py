#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
客户端部署脚本 - 构建并运行 Flutter 客户端
"""
import subprocess
import sys
import os
from pathlib import Path


def main():
    # 获取项目根目录
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    client_dir = project_root / 'client'
    
    print(f"项目根目录: {project_root}")
    print(f"客户端目录: {client_dir}")
    
    if not client_dir.exists():
        print(f"错误: 客户端目录不存在: {client_dir}")
        sys.exit(1)
    
    # 切换到客户端目录
    os.chdir(client_dir)
    print(f"当前工作目录: {os.getcwd()}")
    
    # 1. 获取依赖
    print("\n=== 获取依赖 ===")
    result = subprocess.run(
        ['flutter', 'pub', 'get'],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"获取依赖失败: {result.stderr}")
        sys.exit(1)
    print("依赖获取成功")
    
    # 2. 运行客户端 (macOS)
    print("\n=== 运行客户端 ===")
    result = subprocess.run(
        ['flutter', 'run', '-d', 'macos'],
        capture_output=False  # 实时输出
    )
    
    if result.returncode != 0:
        print(f"运行失败，退出码: {result.returncode}")
        sys.exit(1)
    
    print("客户端已退出")


if __name__ == '__main__':
    main()
