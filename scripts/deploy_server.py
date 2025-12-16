#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
服务端部署脚本 - 构建并运行 Flutter 服务端（Android）
"""
import subprocess
import sys
import os
from pathlib import Path


def main():
    # 获取项目根目录
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    server_dir = project_root / 'server'
    
    print(f"项目根目录: {project_root}")
    print(f"服务端目录: {server_dir}")
    
    if not server_dir.exists():
        print(f"错误: 服务端目录不存在: {server_dir}")
        sys.exit(1)
    
    # 切换到服务端目录
    os.chdir(server_dir)
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
    
    # 2. 检查已连接的 Android 设备
    print("\n=== 检查 Android 设备 ===")
    result = subprocess.run(
        ['flutter', 'devices', '--machine'],
        capture_output=True,
        text=True
    )
    
    # 解析设备列表，找到 Android 设备
    import json
    android_device_id = None
    try:
        devices = json.loads(result.stdout)
        for device in devices:
            if device.get('targetPlatform', '').startswith('android'):
                android_device_id = device.get('id')
                device_name = device.get('name', 'Unknown')
                print(f"找到 Android 设备: {device_name} ({android_device_id})")
                break
    except json.JSONDecodeError:
        print(f"无法解析设备列表: {result.stdout}")
    
    if not android_device_id:
        print("错误: 未找到已连接的 Android 设备")
        print("请确保 Android 设备已连接并启用 USB 调试")
        sys.exit(1)
    
    # 3. 运行服务端 (Android)
    print("\n=== 运行服务端 ===")
    result = subprocess.run(
        ['flutter', 'run', '-d', android_device_id],
        capture_output=False  # 实时输出
    )
    
    if result.returncode != 0:
        print(f"运行失败，退出码: {result.returncode}")
        sys.exit(1)
    
    print("服务端已退出")


if __name__ == '__main__':
    main()
