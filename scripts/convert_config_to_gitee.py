#!/usr/bin/env python3
"""
将 GitHub 更新配置转换为 Gitee 格式

该脚本用于将 GitHub 的更新配置文件转换为 Gitee 格式。
主要修改下载 URL 和更新检查 URL。

用法:
    python3 scripts/convert_config_to_gitee.py \
        --input update_config_github.json \
        --gitee-repo-owner firoyang \
        --gitee-repo-name HelloKnightRemoteCam \
        --output update_config_gitee.json
"""

import argparse
import json
import sys
from pathlib import Path


def convert_to_gitee(
    input_file: str,
    gitee_repo_owner: str,
    gitee_repo_name: str,
    output_file: str,
) -> None:
    """
    将 GitHub 配置转换为 Gitee 格式
    
    Args:
        input_file: 输入的 GitHub 配置文件路径
        gitee_repo_owner: Gitee 仓库所有者
        gitee_repo_name: Gitee 仓库名称
        output_file: 输出的 Gitee 配置文件路径
    """
    # 读取 GitHub 配置
    with open(input_file, 'r', encoding='utf-8') as f:
        config = json.load(f)
    
    gitee_repo = f"{gitee_repo_owner}/{gitee_repo_name}"
    config_release_tag = "config"
    
    # 修改更新检查 URL
    config['updateCheckUrl'] = f"https://gitee.com/{gitee_repo}/releases/download/{config_release_tag}/update_config_gitee.json"
    
    # 修改客户端平台的下载 URL
    import re
    if 'client' in config and 'platforms' in config['client']:
        for platform in ['macos', 'windows']:
            if platform in config['client']['platforms']:
                download_url = config['client']['platforms'][platform].get('downloadUrl', '')
                # 将 github.com 替换为 gitee.com
                if 'github.com' in download_url:
                    # 匹配 github.com/owner/repo/releases/download/tag/file 格式
                    pattern = r'https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/(.+)'
                    match = re.match(pattern, download_url)
                    if match:
                        # 提取文件名部分
                        filename = match.group(4)
                        release_tag = match.group(3)
                        # 构建 Gitee URL
                        new_url = f"https://gitee.com/{gitee_repo}/releases/download/{release_tag}/{filename}"
                        config['client']['platforms'][platform]['downloadUrl'] = new_url
                    else:
                        # 简单替换（fallback）
                        config['client']['platforms'][platform]['downloadUrl'] = download_url.replace('github.com', 'gitee.com')
    
    # 修改服务端平台的下载 URL
    if 'server' in config and 'platforms' in config['server']:
        for platform in ['android']:
            if platform in config['server']['platforms']:
                download_url = config['server']['platforms'][platform].get('downloadUrl', '')
                # 将 github.com 替换为 gitee.com
                if 'github.com' in download_url:
                    # 匹配 github.com/owner/repo/releases/download/tag/file 格式
                    pattern = r'https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/(.+)'
                    match = re.match(pattern, download_url)
                    if match:
                        # 提取文件名部分
                        filename = match.group(4)
                        release_tag = match.group(3)
                        # 构建 Gitee URL
                        new_url = f"https://gitee.com/{gitee_repo}/releases/download/{release_tag}/{filename}"
                        config['server']['platforms'][platform]['downloadUrl'] = new_url
                    else:
                        # 简单替换（fallback）
                        config['server']['platforms'][platform]['downloadUrl'] = download_url.replace('github.com', 'gitee.com')
    
    # 写入 Gitee 配置
    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    
    print(f"✅ Gitee 配置文件已生成: {output_path}")
    print(f"   文件大小: {output_path.stat().st_size} bytes")
    
    # 验证 JSON 格式
    try:
        with open(output_path, 'r', encoding='utf-8') as f:
            json.load(f)
        print("✅ JSON 格式验证通过")
    except json.JSONDecodeError as e:
        print(f"❌ JSON 格式验证失败: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="将 GitHub 更新配置转换为 Gitee 格式",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        "--input",
        required=True,
        help="输入的 GitHub 配置文件路径"
    )
    parser.add_argument(
        "--gitee-repo-owner",
        required=True,
        help="Gitee 仓库所有者"
    )
    parser.add_argument(
        "--gitee-repo-name",
        required=True,
        help="Gitee 仓库名称"
    )
    parser.add_argument(
        "--output",
        required=True,
        help="输出的 Gitee 配置文件路径"
    )
    
    args = parser.parse_args()
    
    try:
        # 验证输入文件存在
        if not os.path.exists(args.input):
            print(f"❌ 错误: 输入文件不存在: {args.input}", file=sys.stderr)
            sys.exit(1)
        
        # 转换配置
        convert_to_gitee(
            input_file=args.input,
            gitee_repo_owner=args.gitee_repo_owner,
            gitee_repo_name=args.gitee_repo_name,
            output_file=args.output,
        )
        
    except Exception as e:
        print(f"❌ 错误: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    import os
    main()

