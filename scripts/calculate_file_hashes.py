#!/usr/bin/env python3
"""
计算文件列表的 SHA256 hash 并生成 JSON 文件

该脚本用于计算指定目录中所有文件的 SHA256 hash，并生成一个 JSON 文件。
JSON 文件格式为字典，key 是文件名，value 是 hash 值。

用法:
    python3 scripts/calculate_file_hashes.py \
        --input-dir artifacts/ \
        --output file_hashes.json
"""

import argparse
import hashlib
import json
import os
import sys
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


def calculate_hashes_for_directory(input_dir: str) -> dict:
    """
    计算目录中所有文件的 hash
    
    Args:
        input_dir: 输入目录路径
        
    Returns:
        字典，key 是文件名，value 是 hash 值
    """
    if not os.path.isdir(input_dir):
        raise NotADirectoryError(f"目录不存在: {input_dir}")
    
    file_hashes = {}
    
    # 遍历目录中的所有文件
    for root, dirs, files in os.walk(input_dir):
        for file_name in files:
            file_path = os.path.join(root, file_name)
            relative_path = os.path.relpath(file_path, input_dir)
            
            # 只处理文件，跳过目录
            if os.path.isfile(file_path):
                try:
                    file_hash = calculate_file_hash(file_path)
                    # 使用相对路径作为 key（相对于输入目录）
                    file_hashes[relative_path] = file_hash
                    print(f"计算 hash: {relative_path} -> {file_hash}")
                except Exception as e:
                    print(f"❌ 计算文件 hash 失败: {relative_path} - {e}", file=sys.stderr)
                    sys.exit(1)
    
    return file_hashes


def main():
    parser = argparse.ArgumentParser(
        description="计算文件列表的 SHA256 hash 并生成 JSON 文件",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        "--input-dir",
        required=True,
        help="输入目录路径（将计算该目录中所有文件的 hash）"
    )
    
    parser.add_argument(
        "--output",
        required=True,
        help="输出 JSON 文件路径"
    )
    
    parser.add_argument(
        "--base-name-only",
        action="store_true",
        help="只使用文件名（不包含路径）作为 key，而不是相对路径"
    )
    
    args = parser.parse_args()
    
    try:
        # 计算 hash
        print(f"📁 输入目录: {os.path.abspath(args.input_dir)}")
        file_hashes = calculate_hashes_for_directory(args.input_dir)
        
        if not file_hashes:
            print("⚠️  警告: 未找到任何文件", file=sys.stderr)
            sys.exit(1)
        
        # 如果指定了 --base-name-only，只使用文件名作为 key
        if args.base_name_only:
            file_hashes_base = {}
            for relative_path, file_hash in file_hashes.items():
                file_name = os.path.basename(relative_path)
                # 如果有重名文件，保留最后一个（或可以报错）
                if file_name in file_hashes_base:
                    print(f"⚠️  警告: 发现重名文件，将覆盖: {file_name}", file=sys.stderr)
                file_hashes_base[file_name] = file_hash
            file_hashes = file_hashes_base
        
        # 写入 JSON 文件
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(file_hashes, f, indent=2, ensure_ascii=False)
        
        print(f"\n✅ Hash 文件已生成: {os.path.abspath(args.output)}")
        print(f"   文件数量: {len(file_hashes)}")
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

