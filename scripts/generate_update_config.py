#!/usr/bin/env python3
"""
生成更新配置文件脚本

该脚本用于生成 GitHub 和 Gitee 的更新配置文件。
支持从文件计算 SHA256 hash，并生成符合格式的 JSON 配置文件。

用法:
    python3 scripts/generate_update_config.py \
        --client-version 1.0.7+10 \
        --server-version 1.0.7+10 \
        --macos-file artifacts/HelloKnightRCC_macos_1.0.7+10.zip \
        --windows-file artifacts/HelloKnightRCC_windows_1.0.7+10.zip \
        --android-file artifacts/helloknightrcc_server_android_1.0.7+10.zip \
        --tag-version v1.0.7 \
        --repo-owner shichao402 \
        --repo-name HelloKnightRemoteCam \
        --output update_config_github.json
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def calculate_file_hash(file_path: str) -> str:
    """
    计算文件的 SHA256 hash
    
    Args:
        file_path: 文件路径
        
    Returns:
        SHA256 hash 值（小写，64字符）
    """
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"文件不存在: {file_path}")
    
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        # 分块读取，避免大文件占用过多内存
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    
    return sha256_hash.hexdigest().lower()


def extract_version_number(full_version: str) -> str:
    """
    从完整版本号中提取主版本号（去除构建号）
    
    Args:
        full_version: 完整版本号，格式如 "1.0.7+10"
        
    Returns:
        主版本号，格式如 "1.0.7"
    """
    if '+' in full_version:
        return full_version.split('+')[0]
    return full_version


def generate_update_config(
    client_version: str,
    server_version: str,
    macos_file: str,
    windows_file: str,
    android_file: str,
    tag_version: str,
    repo_owner: str,
    repo_name: str,
    base_url: str = None,
    update_check_url: str = None,
    repo_type: str = "github",
) -> dict:
    """
    生成更新配置 JSON
    
    Args:
        client_version: 客户端完整版本号（如 "1.0.7+10"）
        server_version: 服务端完整版本号（如 "1.0.7+10"）
        macos_file: macOS ZIP 文件路径
        windows_file: Windows ZIP 文件路径
        android_file: Android ZIP 文件路径
        tag_version: Release 标签（如 "v1.0.7"）
        repo_owner: 仓库所有者
        repo_name: 仓库名称
        base_url: 下载基础 URL（可选，默认使用 GitHub Releases）
        update_check_url: 更新检查 URL（可选，默认使用 GitHub）
        
    Returns:
        更新配置字典
    """
    # 提取主版本号
    client_version_number = extract_version_number(client_version)
    server_version_number = extract_version_number(server_version)
    
    # 构建文件名
    macos_filename = os.path.basename(macos_file)
    windows_filename = os.path.basename(windows_file)
    android_filename = os.path.basename(android_file)
    
    # 计算文件 hash
    print(f"计算 macOS 文件 hash: {macos_file}")
    macos_hash = calculate_file_hash(macos_file)
    print(f"  Hash: {macos_hash}")
    
    print(f"计算 Windows 文件 hash: {windows_file}")
    windows_hash = calculate_file_hash(windows_file)
    print(f"  Hash: {windows_hash}")
    
    print(f"计算 Android 文件 hash: {android_file}")
    android_hash = calculate_file_hash(android_file)
    print(f"  Hash: {android_hash}")
    
    # 构建下载 URL（根据 repo_type 使用不同的 URL 前缀）
    if base_url is None:
        if repo_type == "gitee":
            base_url = f"https://gitee.com/{repo_owner}/{repo_name}/releases/download/{tag_version}"
        else:
            base_url = f"https://github.com/{repo_owner}/{repo_name}/releases/download/{tag_version}"
    
    if update_check_url is None:
        if repo_type == "gitee":
            # Gitee 使用固定的 "config" tag
            update_check_url = f"https://gitee.com/{repo_owner}/{repo_name}/releases/download/config/update_config_gitee.json"
        else:
            # GitHub 使用固定的 "UpdateConfig" tag
            update_check_url = f"https://github.com/{repo_owner}/{repo_name}/releases/download/UpdateConfig/update_config_github.json"
    
    # 生成配置
    config = {
        "client": {
            "version": client_version,
            "versionNumber": client_version_number,
            "platforms": {
                "macos": {
                    "version": client_version,
                    "versionNumber": client_version_number,
                    "downloadUrl": f"{base_url}/{macos_filename}",
                    "fileName": macos_filename,
                    "fileType": "zip",
                    "platform": "macos",
                    "fileHash": macos_hash
                },
                "windows": {
                    "version": client_version,
                    "versionNumber": client_version_number,
                    "downloadUrl": f"{base_url}/{windows_filename}",
                    "fileName": windows_filename,
                    "fileType": "zip",
                    "platform": "windows",
                    "fileHash": windows_hash
                }
            }
        },
        "server": {
            "version": server_version,
            "versionNumber": server_version_number,
            "platforms": {
                "android": {
                    "version": server_version,
                    "versionNumber": server_version_number,
                    "downloadUrl": f"{base_url}/{android_filename}",
                    "fileName": android_filename,
                    "fileType": "zip",
                    "platform": "android",
                    "fileHash": android_hash
                }
            }
        },
        "updateCheckUrl": update_check_url,
        "lastUpdated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    
    return config


def main():
    parser = argparse.ArgumentParser(
        description="生成更新配置文件",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        "--client-version",
        required=True,
        help="客户端完整版本号（如 1.0.7+10）"
    )
    parser.add_argument(
        "--server-version",
        required=True,
        help="服务端完整版本号（如 1.0.7+10）"
    )
    parser.add_argument(
        "--macos-file",
        required=True,
        help="macOS ZIP 文件路径"
    )
    parser.add_argument(
        "--windows-file",
        required=True,
        help="Windows ZIP 文件路径"
    )
    parser.add_argument(
        "--android-file",
        required=True,
        help="Android ZIP 文件路径"
    )
    parser.add_argument(
        "--tag-version",
        required=True,
        help="Release 标签（如 v1.0.7）"
    )
    parser.add_argument(
        "--repo-owner",
        required=True,
        help="仓库所有者"
    )
    parser.add_argument(
        "--repo-name",
        required=True,
        help="仓库名称"
    )
    parser.add_argument(
        "--base-url",
        help="下载基础 URL（可选，默认使用 GitHub Releases）"
    )
    parser.add_argument(
        "--update-check-url",
        help="更新检查 URL（可选，默认使用 GitHub）"
    )
    parser.add_argument(
        "--repo-type",
        choices=["github", "gitee"],
        default="github",
        help="仓库类型（github 或 gitee，默认 github）"
    )
    parser.add_argument(
        "--output",
        required=True,
        help="输出文件路径"
    )
    
    args = parser.parse_args()
    
    try:
        # 验证文件存在
        for file_path, name in [
            (args.macos_file, "macOS"),
            (args.windows_file, "Windows"),
            (args.android_file, "Android"),
        ]:
            if not os.path.exists(file_path):
                print(f"❌ 错误: {name} 文件不存在: {file_path}", file=sys.stderr)
                sys.exit(1)
        
        # 生成配置
        config = generate_update_config(
            client_version=args.client_version,
            server_version=args.server_version,
            macos_file=args.macos_file,
            windows_file=args.windows_file,
            android_file=args.android_file,
            tag_version=args.tag_version,
            repo_owner=args.repo_owner,
            repo_name=args.repo_name,
            base_url=args.base_url,
            update_check_url=args.update_check_url,
            repo_type=args.repo_type,
        )
        
        # 写入文件
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        print(f"\n✅ 更新配置文件已生成: {output_path}")
        print(f"   文件大小: {output_path.stat().st_size} bytes")
        
        # 验证 JSON 格式
        try:
            with open(output_path, 'r', encoding='utf-8') as f:
                json.load(f)
            print("✅ JSON 格式验证通过")
        except json.JSONDecodeError as e:
            print(f"❌ JSON 格式验证失败: {e}", file=sys.stderr)
            sys.exit(1)
        
    except Exception as e:
        print(f"❌ 错误: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

