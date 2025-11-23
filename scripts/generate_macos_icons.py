#!/usr/bin/env python3
"""
从 assets 中的原始图标生成 macOS 图标
- 从原始图标（assets/AppIcon/taskP/ios/AppIcon~ios-marketing.png）开始
- 添加 macOS 风格的圆角
- 调整内容区域到 85%（符合 Apple HIG 指南）
- 生成所有 macOS 需要的尺寸
"""

import os
import sys
from PIL import Image, ImageDraw
import math

def add_rounded_corners(image, corner_radius):
    """
    为图像添加圆角
    
    Args:
        image: PIL Image 对象
        corner_radius: 圆角半径（像素）
    
    Returns:
        带圆角的 PIL Image 对象
    """
    # 创建圆角遮罩
    mask = Image.new('L', image.size, 0)
    draw = ImageDraw.Draw(mask)
    
    # 绘制圆角矩形
    width, height = image.size
    draw.rounded_rectangle(
        [(0, 0), (width, height)],
        radius=corner_radius,
        fill=255
    )
    
    # 应用遮罩
    output = Image.new('RGBA', image.size, (0, 0, 0, 0))
    output.paste(image, (0, 0), mask)
    
    return output

def generate_macos_icon_from_source(source_path, target_size, content_percent=0.85):
    """
    从源图标生成指定尺寸的 macOS 图标
    
    Args:
        source_path: 源图标路径
        target_size: 目标尺寸（如 1024）
        content_percent: 内容区域占画布的百分比（默认85%）
    
    Returns:
        PIL Image 对象
    """
    # 打开源图标
    source_img = Image.open(source_path).convert('RGBA')
    source_width, source_height = source_img.size
    
    # 确保源图像是方形的
    if source_width != source_height:
        # 裁剪为正方形（居中）
        size = min(source_width, source_height)
        left = (source_width - size) // 2
        top = (source_height - size) // 2
        source_img = source_img.crop((left, top, left + size, top + size))
        source_width = source_height = size
    
    # 计算目标内容区域大小（85%）
    target_content_size = int(target_size * content_percent)
    padding = (target_size - target_content_size) // 2
    
    # 将源图标缩放到目标内容尺寸
    content_img = source_img.resize(
        (target_content_size, target_content_size),
        Image.Resampling.LANCZOS
    )
    
    # 添加 macOS 风格的圆角（圆角半径约为图像尺寸的 20%，但不超过 80 像素）
    corner_radius = min(int(target_size * 0.2), 80)
    rounded_content = add_rounded_corners(content_img, corner_radius)
    
    # 创建新的透明画布
    final_img = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))
    
    # 将圆角内容居中放置
    final_img.paste(rounded_content, (padding, padding), rounded_content)
    
    return final_img

def main():
    """主函数"""
    print("=" * 60)
    print("macOS 图标生成脚本")
    print("从 assets 原始图标生成 macOS 圆角图标")
    print("内容区域：85%（符合 Apple HIG 指南）")
    print("=" * 60)
    print()
    
    # 切换到项目根目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    os.chdir(project_root)
    
    print(f"工作目录: {os.getcwd()}")
    print()
    
    # 查找原始图标（优先使用 iOS marketing icon，通常是 1024x1024）
    source_icon_paths = [
        "assets/AppIcon/taskP/ios/AppIcon~ios-marketing.png",
        "assets/AppIcon/taskP/web/icon-512.png",
        "assets/AppIcon/taskP/android/play_store_512.png",
    ]
    
    source_icon_path = None
    source_img = None
    
    for path in source_icon_paths:
        if os.path.exists(path):
            try:
                test_img = Image.open(path)
                source_icon_path = path
                source_img = test_img
                print(f"✓ 找到原始图标: {path} ({test_img.size[0]}x{test_img.size[1]})")
                break
            except Exception as e:
                print(f"警告: 无法打开 {path}: {e}")
                continue
    
    if source_icon_path is None:
        print("❌ 错误: 找不到原始图标文件")
        print("   请确保以下文件之一存在:")
        for path in source_icon_paths:
            print(f"   - {path}")
        return 1
    
    # macOS 图标目录
    icon_dir = "client/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    
    if not os.path.exists(icon_dir):
        print(f"❌ 错误: {icon_dir} 不存在")
        return 1
    
    # macOS 需要的图标尺寸（@1x 和 @2x）
    # 格式: (size_name, 1x_size, 2x_size)
    icon_sizes = [
        ("16", 16, 32),
        ("32", 32, 64),
        ("128", 128, 256),
        ("256", 256, 512),
        ("512", 512, 1024),
    ]
    
    # 还需要单独的 1024x1024（用于 @2x 512x512）
    icon_files = {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    
    success_count = 0
    for icon_file, size in icon_files.items():
        icon_path = os.path.join(icon_dir, icon_file)
        
        try:
            # 生成图标
            icon_img = generate_macos_icon_from_source(source_icon_path, size, content_percent=0.85)
            
            # 保存
            icon_img.save(icon_path, 'PNG', optimize=True)
            
            # 计算实际内容区域
            bbox = icon_img.getbbox()
            if bbox:
                left, top, right, bottom = bbox
                content_size = right - left
                content_percent_actual = (content_size / size) * 100
                print(f"✓ 已生成: {icon_file} ({size}x{size}, 内容区域: {content_size}x{content_size} ({content_percent_actual:.1f}%))")
            else:
                print(f"✓ 已生成: {icon_file} ({size}x{size})")
            
            success_count += 1
        except Exception as e:
            print(f"❌ 错误: 生成 {icon_file} 失败: {e}")
            import traceback
            traceback.print_exc()
    
    print()
    print("=" * 60)
    if success_count == len(icon_files):
        print(f"✓ 成功生成 {success_count} 个 macOS 图标文件")
        print("=" * 60)
        return 0
    else:
        print(f"✗ 部分图标生成失败（成功: {success_count}/{len(icon_files)}）")
        print("=" * 60)
        return 1

if __name__ == "__main__":
    sys.exit(main())

