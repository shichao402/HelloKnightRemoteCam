#!/usr/bin/env python3
"""
恢复 macOS 图标尺寸，将图标内容放大到占满画布的 95%
根据 Apple HIG 指南，图标内容应该占据画布的 80-90%，但用户反馈图标太小
这里将内容区域设置为 95%，只保留很小的内边距（2.5%）
"""

import os
import sys
from PIL import Image

def restore_icon_size(icon_path, content_percent=0.90):
    """
    恢复图标尺寸，将内容放大到指定百分比
    
    Args:
        icon_path: 图标文件路径
        content_percent: 内容区域占画布的百分比（默认90%，符合 Apple HIG 指南）
    
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
        
        # 找到当前内容的边界框
        bbox = img.getbbox()
        if not bbox:
            print(f"警告: {icon_path} 完全透明，跳过")
            return False
        
        left, top, right, bottom = bbox
        current_content_width = right - left
        current_content_height = bottom - top
        
        # 计算目标内容区域大小（90%）
        target_content_size = int(width * content_percent)
        padding = (width - target_content_size) // 2
        
        # 提取当前内容区域
        current_content = img.crop((left, top, right, bottom))
        
        # 将内容放大到目标尺寸
        resized_content = current_content.resize(
            (target_content_size, target_content_size),
            Image.Resampling.LANCZOS
        )
        
        # 创建新的透明画布
        new_img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
        
        # 将放大后的内容居中放置
        new_img.paste(resized_content, (padding, padding), resized_content)
        
        # 保存
        new_img.save(icon_path, 'PNG', optimize=True)
        actual_content_percent = (target_content_size / width) * 100
        print(f"✓ 已恢复: {os.path.basename(icon_path)} ({width}x{width}, 内容区域: {target_content_size}x{target_content_size} ({actual_content_percent:.1f}%), 内边距: {padding}px)")
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
    print("将图标内容调整到占满画布的 90%")
    print("符合 Apple HIG 指南：图标内容应占据画布的 80-90%")
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
        
        if restore_icon_size(icon_path):
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

