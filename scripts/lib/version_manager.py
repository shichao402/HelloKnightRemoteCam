#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
统一的版本号管理模块
所有版本号的读写操作都通过此模块完成
"""

import yaml
import sys
import re
import os
import json
from typing import Optional, Tuple, Dict, Any

# 修复 Windows 上的编码问题
if sys.platform == 'win32':
    # Windows 上设置标准输出为 UTF-8
    if sys.stdout.encoding != 'utf-8':
        try:
            sys.stdout.reconfigure(encoding='utf-8')
        except AttributeError:
            # Python < 3.7 不支持 reconfigure
            import io
            sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    
    if sys.stderr.encoding != 'utf-8':
        try:
            sys.stderr.reconfigure(encoding='utf-8')
        except AttributeError:
            # Python < 3.7 不支持 reconfigure
            import io
            sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


class VersionManager:
    """版本号管理器"""
    
    def __init__(self, project_root: Optional[str] = None):
        """
        初始化版本管理器
        
        Args:
            project_root: 项目根目录路径，如果为None则自动检测
        """
        if project_root is None:
            # 自动检测项目根目录（脚本所在目录的父目录的父目录，因为脚本在 scripts/lib/ 下）
            script_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.dirname(os.path.dirname(script_dir))
        
        self.project_root = os.path.abspath(project_root)
        self.version_file_yaml = os.path.join(self.project_root, 'VERSION.yaml')
        self.version_file_old = os.path.join(self.project_root, 'VERSION')
    
    def _load_yaml(self) -> Dict[str, Any]:
        """加载 YAML 文件"""
        if not os.path.exists(self.version_file_yaml):
            raise FileNotFoundError(f"VERSION.yaml 文件不存在: {self.version_file_yaml}")
        
        with open(self.version_file_yaml, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    
    def _save_yaml(self, data: Dict[str, Any]) -> None:
        """保存 YAML 文件"""
        with open(self.version_file_yaml, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    def _load_old_format(self) -> Dict[str, str]:
        """加载旧格式 VERSION 文件"""
        if not os.path.exists(self.version_file_old):
            raise FileNotFoundError(f"VERSION 文件不存在: {self.version_file_old}")
        
        result = {}
        with open(self.version_file_old, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if '=' in line:
                    key, value = line.split('=', 1)
                    result[key.strip()] = value.strip()
        return result
    
    def _get_version_file_type(self) -> str:
        """获取版本文件类型"""
        if os.path.exists(self.version_file_yaml):
            return 'yaml'
        elif os.path.exists(self.version_file_old):
            return 'old'
        else:
            raise FileNotFoundError("VERSION.yaml 或 VERSION 文件都不存在")
    
    def get_version(self, target: str) -> str:
        """
        获取版本号
        
        Args:
            target: 'client' 或 'server'
        
        Returns:
            版本号字符串，格式: x.y.z+build
        """
        file_type = self._get_version_file_type()
        
        if file_type == 'yaml':
            data = self._load_yaml()
            if target == 'client':
                version = data.get('client', {}).get('version', '')
            elif target == 'server':
                version = data.get('server', {}).get('version', '')
            else:
                raise ValueError(f"未知目标: {target}")
            
            if not version:
                raise ValueError(f"无法从 VERSION.yaml 读取{target}版本号")
            
            return version
        else:
            # 旧格式
            data = self._load_old_format()
            key = 'CLIENT_VERSION' if target == 'client' else 'SERVER_VERSION'
            version = data.get(key, '')
            
            if not version:
                raise ValueError(f"无法从 VERSION 文件读取{target}版本号")
            
            return version
    
    def set_version(self, target: str, version: str) -> None:
        """
        设置版本号
        
        Args:
            target: 'client' 或 'server'
            version: 版本号字符串，格式: x.y.z+build
        """
        self.validate_version(version)
        
        file_type = self._get_version_file_type()
        
        if file_type == 'yaml':
            data = self._load_yaml()
            if target == 'client':
                if 'client' not in data:
                    data['client'] = {}
                data['client']['version'] = version
            elif target == 'server':
                if 'server' not in data:
                    data['server'] = {}
                data['server']['version'] = version
            else:
                raise ValueError(f"未知目标: {target}")
            
            self._save_yaml(data)
        else:
            # 旧格式
            data = self._load_old_format()
            key = 'CLIENT_VERSION' if target == 'client' else 'SERVER_VERSION'
            data[key] = version
            
            # 写回文件
            with open(self.version_file_old, 'w', encoding='utf-8') as f:
                for key, value in data.items():
                    f.write(f"{key}={value}\n")
    
    def get_min_version(self, target: str) -> str:
        """
        获取最小版本号
        
        Args:
            target: 'client' 或 'server'
        
        Returns:
            最小版本号字符串，格式: x.y.z（不含构建号）
        """
        file_type = self._get_version_file_type()
        
        if file_type == 'yaml':
            data = self._load_yaml()
            if target == 'client':
                version = data.get('compatibility', {}).get('min_client_version', '')
            elif target == 'server':
                version = data.get('compatibility', {}).get('min_server_version', '')
            else:
                raise ValueError(f"未知目标: {target}")
            
            if not version:
                raise ValueError(f"无法从 VERSION.yaml 读取{target}最小版本号")
            
            return version
        else:
            # 旧格式不支持最小版本号
            raise ValueError("旧格式 VERSION 文件不支持最小版本号")
    
    def set_min_version(self, target: str, min_version: str) -> None:
        """
        设置最小版本号
        
        Args:
            target: 'client' 或 'server'
            min_version: 最小版本号字符串，格式: x.y.z（不含构建号）
        """
        if not re.match(r'^\d+\.\d+\.\d+$', min_version):
            raise ValueError(f"最小版本号格式不正确: {min_version} (应为 x.y.z 格式)")
        
        file_type = self._get_version_file_type()
        
        if file_type == 'yaml':
            data = self._load_yaml()
            if 'compatibility' not in data:
                data['compatibility'] = {}
            
            if target == 'client':
                data['compatibility']['min_client_version'] = min_version
            elif target == 'server':
                data['compatibility']['min_server_version'] = min_version
            else:
                raise ValueError(f"未知目标: {target}")
            
            self._save_yaml(data)
        else:
            raise ValueError("旧格式 VERSION 文件不支持最小版本号")
    
    @staticmethod
    def validate_version(version: str) -> None:
        """
        验证版本号格式
        
        Args:
            version: 版本号字符串
        
        Raises:
            ValueError: 如果版本号格式不正确
        """
        if not re.match(r'^\d+\.\d+\.\d+(\+\d+)?$', version):
            raise ValueError(f"版本号格式不正确: {version} (应为 x.y.z+build 或 x.y.z 格式)")
    
    @staticmethod
    def parse_version(version: str) -> Tuple[str, str]:
        """
        解析版本号字符串
        
        Args:
            version: 版本号字符串，格式: x.y.z+build 或 x.y.z
        
        Returns:
            (version_part, build_part) 元组
        """
        if '+' in version:
            version_part, build_part = version.rsplit('+', 1)
        else:
            version_part = version
            build_part = '1'
        
        # 验证版本号格式
        if not re.match(r'^\d+\.\d+\.\d+$', version_part):
            raise ValueError(f"版本号格式不正确: {version_part} (应为 x.y.z 格式)")
        
        # 验证构建号
        if not build_part.isdigit():
            build_part = '1'
        
        return version_part, build_part
    
    def bump_version(self, target: str, bump_type: str) -> str:
        """
        递增版本号
        
        Args:
            target: 'client' 或 'server'
            bump_type: 'major', 'minor', 'patch', 或 'build'
        
        Returns:
            新的版本号字符串
        """
        current_version = self.get_version(target)
        version_part, build_part = self.parse_version(current_version)
        
        major, minor, patch = map(int, version_part.split('.'))
        build_number = int(build_part)
        
        if bump_type == 'major':
            major += 1
            minor = 0
            patch = 0
        elif bump_type == 'minor':
            minor += 1
            patch = 0
        elif bump_type == 'patch':
            patch += 1
        elif bump_type == 'build':
            build_number += 1
        else:
            raise ValueError(f"未知的递增类型: {bump_type} (应为 major, minor, patch, 或 build)")
        
        new_version = f"{major}.{minor}.{patch}+{build_number}"
        self.set_version(target, new_version)
        
        return new_version
    
    def sync_to_pubspec(self, target: str, pubspec_path: Optional[str] = None) -> None:
        """
        同步版本号到 pubspec.yaml
        
        Args:
            target: 'client' 或 'server'
            pubspec_path: pubspec.yaml 文件路径，如果为None则自动检测
        """
        version = self.get_version(target)
        version_part, build_part = self.parse_version(version)
        full_version = f"{version_part}+{build_part}"
        
        if pubspec_path is None:
            if target == 'client':
                pubspec_path = os.path.join(self.project_root, 'client', 'pubspec.yaml')
            elif target == 'server':
                pubspec_path = os.path.join(self.project_root, 'server', 'pubspec.yaml')
            else:
                raise ValueError(f"未知目标: {target}")
        
        if not os.path.exists(pubspec_path):
            raise FileNotFoundError(f"pubspec.yaml 文件不存在: {pubspec_path}")
        
        # 读取文件内容
        with open(pubspec_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 替换版本号行
        pattern = r'^version:\s*.*$'
        replacement = f'version: {full_version}'
        new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
        
        # 写回文件
        with open(pubspec_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
    
    def copy_to_assets(self) -> None:
        """复制 VERSION.yaml 文件到服务器 assets 目录"""
        assets_dir = os.path.join(self.project_root, 'server', 'assets')
        os.makedirs(assets_dir, exist_ok=True)
        
        file_type = self._get_version_file_type()
        
        if file_type == 'yaml':
            import shutil
            shutil.copy2(self.version_file_yaml, os.path.join(assets_dir, 'VERSION.yaml'))
        else:
            import shutil
            shutil.copy2(self.version_file_old, os.path.join(assets_dir, 'VERSION'))
    
    def get_all_info(self) -> Dict[str, Any]:
        """
        获取所有版本信息
        
        Returns:
            包含所有版本信息的字典
        """
        try:
            client_version = self.get_version('client')
            server_version = self.get_version('server')
            
            client_version_part, client_build = self.parse_version(client_version)
            server_version_part, server_build = self.parse_version(server_version)
            
            result = {
                'client': {
                    'version': client_version,
                    'version_part': client_version_part,
                    'build_number': client_build,
                    'full_version': f"{client_version_part}+{client_build}"
                },
                'server': {
                    'version': server_version,
                    'version_part': server_version_part,
                    'build_number': server_build,
                    'full_version': f"{server_version_part}+{server_build}"
                }
            }
            
            # 尝试获取最小版本号
            try:
                result['compatibility'] = {
                    'min_client_version': self.get_min_version('client'),
                    'min_server_version': self.get_min_version('server')
                }
            except (ValueError, FileNotFoundError):
                pass
            
            return result
        except Exception as e:
            raise RuntimeError(f"获取版本信息失败: {e}")


def main():
    """命令行接口"""
    import argparse
    
    parser = argparse.ArgumentParser(description='版本号管理工具')
    parser.add_argument('--project-root', help='项目根目录路径')
    
    subparsers = parser.add_subparsers(dest='command', help='命令')
    
    # get 命令
    get_parser = subparsers.add_parser('get', help='获取版本号')
    get_parser.add_argument('target', nargs='?', choices=['client', 'server', 'all'], default='all',
                           help='目标 (client/server/all)')
    get_parser.add_argument('--json', action='store_true', help='输出 JSON 格式')
    
    # set 命令
    set_parser = subparsers.add_parser('set', help='设置版本号')
    set_parser.add_argument('target', choices=['client', 'server'], help='目标')
    set_parser.add_argument('version', help='版本号 (格式: x.y.z+build)')
    
    # bump 命令
    bump_parser = subparsers.add_parser('bump', help='递增版本号')
    bump_parser.add_argument('target', choices=['client', 'server'], help='目标')
    bump_parser.add_argument('type', choices=['major', 'minor', 'patch', 'build'], help='递增类型')
    
    # sync 命令
    sync_parser = subparsers.add_parser('sync', help='同步版本号到 pubspec.yaml')
    sync_parser.add_argument('target', nargs='?', choices=['client', 'server', 'all'], default='all',
                            help='目标 (client/server/all)')
    sync_parser.add_argument('--pubspec', help='pubspec.yaml 文件路径')
    
    # set-min-version 命令
    min_parser = subparsers.add_parser('set-min-version', help='设置最小版本号')
    min_parser.add_argument('target', choices=['client', 'server'], help='目标')
    min_parser.add_argument('version', help='最小版本号 (格式: x.y.z)')
    
    # extract 命令（用于 GitHub Actions）
    extract_parser = subparsers.add_parser('extract', help='提取版本号（用于 CI/CD）')
    extract_parser.add_argument('target', choices=['client', 'server'], help='目标')
    extract_parser.add_argument('--sync', help='同步到 pubspec.yaml 文件路径')
    extract_parser.add_argument('--json', action='store_true', default=True, help='输出 JSON 格式')
    
    # copy-to-assets 命令
    copy_parser = subparsers.add_parser('copy-to-assets', help='拷贝 VERSION.yaml 到 server/assets 目录')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    manager = VersionManager(args.project_root)
    
    try:
        if args.command == 'get':
            if args.target == 'all':
                if args.json:
                    info = manager.get_all_info()
                    print(json.dumps(info, ensure_ascii=False, indent=2))
                else:
                    info = manager.get_all_info()
                    print(f"客户端版本: {info['client']['full_version']}")
                    print(f"服务器版本: {info['server']['full_version']}")
                    if 'compatibility' in info:
                        print(f"最小客户端版本: {info['compatibility']['min_client_version']}")
                        print(f"最小服务器版本: {info['compatibility']['min_server_version']}")
            else:
                version = manager.get_version(args.target)
                if args.json:
                    version_part, build_part = manager.parse_version(version)
                    output = {
                        'version': version_part,
                        'build_number': build_part,
                        'full_version': f"{version_part}+{build_part}",
                        'tag_version': f'v{version_part}'
                    }
                    print(json.dumps(output, ensure_ascii=False))
                else:
                    print(version)
        
        elif args.command == 'set':
            manager.set_version(args.target, args.version)
            print(f"{args.target}版本号已设置为: {args.version}")
        
        elif args.command == 'bump':
            new_version = manager.bump_version(args.target, args.type)
            print(f"{args.target}版本号已递增: {new_version}")
        
        elif args.command == 'sync':
            if args.target == 'all':
                manager.sync_to_pubspec('client', args.pubspec)
                manager.sync_to_pubspec('server', args.pubspec)
                manager.copy_to_assets()
                print("已同步所有版本号到 pubspec.yaml")
            else:
                manager.sync_to_pubspec(args.target, args.pubspec)
                if args.target == 'server':
                    manager.copy_to_assets()
                version = manager.get_version(args.target)
                version_part, build_part = manager.parse_version(version)
                print(f"已同步{args.target}版本号: {version_part}+{build_part}")
        
        elif args.command == 'set-min-version':
            manager.set_min_version(args.target, args.version)
            print(f"{args.target}最小版本号已设置为: {args.version}")
        
        elif args.command == 'extract':
            version = manager.get_version(args.target)
            version_part, build_part = manager.parse_version(version)
            
            if args.sync:
                manager.sync_to_pubspec(args.target, args.sync)
                # 注意：不再在这里自动拷贝 VERSION.yaml 到 assets
                # 拷贝逻辑应该在构建脚本中统一处理，确保本地和 CI/CD 一致
            
            if args.json:
                output = {
                    'version': version_part,
                    'build_number': build_part,
                    'full_version': f"{version_part}+{build_part}",
                    'tag_version': f'v{version_part}'
                }
                print(json.dumps(output, ensure_ascii=False))
            else:
                print(f"{version_part}+{build_part}")
        
        elif args.command == 'copy-to-assets':
            manager.copy_to_assets()
            print("VERSION.yaml 已拷贝到 server/assets 目录")
    
    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

