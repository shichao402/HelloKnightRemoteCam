#!/usr/bin/env python3
"""
调整 macOS 图标尺寸，添加安全内边距
根据 Apple HIG 指南，图标内容应该占据画布的 80-90%，留出 10-20% 的内边距
这样可以确保图标在 Dock 和 Finder 中显示时不会显得过大
"""

import os
import sys
from PIL import Image

def adjust_icon_size(icon_path, padding_percent=0.15):
    """
    调整图标尺寸，添加内边距
    
    Args:
        icon_path: 图标文件路径
        padding_percent: 内边距百分比（默认15%，即图标内容占85%）
    
    Returns:
        bool: 是否成功
    """
    try:
        # 打开图像
        img = Image.open(icon_path).convert('RGBA')
        width, height = img.size
        
        if width != height:
            print(f"警告: {icon_path} 不是正方形 ({width}x{height})，跳过")
            return False
        
        # 计算新的内容区域大小（85%）
        content_size = int(width * (1 - padding_percent * 2))
        padding = (width - content_size) // 2
        
        # 创建新的透明画布
        new_img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
        
        # 将原图缩小并居中放置
        resized_img = img.resize((content_size, content_size), Image.Resampling.LANCZOS)
        new_img.paste(resized_img, (padding, padding), resized_img)
        
        # 保存
        new_img.save(icon_path, 'PNG', optimize=True)
        print(f"✓ 已调整: {os.path.basename(icon_path)} ({width}x{height}, 内容区域: {content_size}x{content_size}, 内边距: {padding}px)")
        return True
    except Exception as e:
        print(f"错误: 处理 {icon_path} 时出错: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """主函数"""
    print("=" * 60)
    print("macOS 图标尺寸调整脚本")
    print("添加安全内边距（15%），使图标内容占85%")
    print("=" * 60)
    print()
    
    # 切换到项目根目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    os.chdir(project_root)
    
    print(f"工作目录: {os.getcwd()}")
    print()
    
    icon_dir = "client/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    
    if not os.path.exists(icon_dir):
        print(f"错误: {icon_dir} 不存在")
        return 1
    
    # 需要处理的图标文件
    icon_files = [
        "app_icon_16.png",
        "app_icon_32.png",
        "app_icon_64.png",
        "app_icon_128.png",
        "app_icon_256.png",
        "app_icon_512.png",
        "app_icon_1024.png",
    ]
    
    success_count = 0
    for icon_file in icon_files:
        icon_path = os.path.join(icon_dir, icon_file)
        if not os.path.exists(icon_path):
            print(f"警告: {icon_path} 不存在，跳过")
            continue
        
        if adjust_icon_size(icon_path):
            success_count += 1
    
    print()
    print("=" * 60)
    if success_count == len([f for f in icon_files if os.path.exists(os.path.join(icon_dir, f))]):
        print(f"✓ 成功处理 {success_count} 个图标文件")
        print("=" * 60)
        return 0
    else:
        print(f"✗ 部分图标处理失败（成功: {success_count}/{len(icon_files)}）")
        print("=" * 60)
        return 1

if __name__ == "__main__":
    sys.exit(main())

