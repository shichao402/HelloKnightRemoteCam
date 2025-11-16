#!/usr/bin/env python3
"""
为应用图标添加背景的脚本
为Mac、Windows和Android平台的所有图标添加实色背景
"""

import os
import sys
from PIL import Image
import shutil

# 定义背景颜色 - 使用实色蓝色背景
BACKGROUND_COLOR = (50, 100, 180)  # 蓝色

def create_solid_background(size, color):
    """创建实色背景"""
    image = Image.new('RGB', size, color)
    return image

def add_background_to_icon(icon_path, output_path=None):
    """为图标添加背景"""
    if output_path is None:
        output_path = icon_path
    
    try:
        # 打开原始图标
        icon = Image.open(icon_path)
        
        # 如果是RGBA模式，分离alpha通道
        if icon.mode == 'RGBA':
            # 创建实色背景
            background = create_solid_background(
                icon.size,
                BACKGROUND_COLOR
            )
            
            # 将背景转换为RGBA
            background = background.convert('RGBA')
            
            # 如果图标有透明区域，使用alpha通道合成
            # 创建一个新的图像，先放置背景，再放置图标
            result = Image.new('RGBA', icon.size, (0, 0, 0, 0))
            result.paste(background, (0, 0))
            result = Image.alpha_composite(result, icon)
            
            # 保存结果
            result.save(output_path, 'PNG')
            print(f"✓ 已处理: {icon_path}")
        else:
            # 如果不是RGBA，转换为RGBA后处理
            icon_rgba = icon.convert('RGBA')
            background = create_solid_background(
                icon_rgba.size,
                BACKGROUND_COLOR
            )
            background = background.convert('RGBA')
            
            result = Image.new('RGBA', icon_rgba.size, (0, 0, 0, 0))
            result.paste(background, (0, 0))
            result = Image.alpha_composite(result, icon_rgba)
            
            result.save(output_path, 'PNG')
            print(f"✓ 已处理: {icon_path}")
            
    except Exception as e:
        print(f"✗ 处理失败 {icon_path}: {e}")
        return False
    
    return True

def process_mac_icons():
    """处理Mac客户端图标"""
    print("\n处理Mac客户端图标...")
    icon_dir = "client/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    
    icon_files = [
        "app_icon_16.png",
        "app_icon_32.png",
        "app_icon_64.png",
        "app_icon_128.png",
        "app_icon_256.png",
        "app_icon_512.png",
        "app_icon_1024.png",
    ]
    
    for icon_file in icon_files:
        icon_path = os.path.join(icon_dir, icon_file)
        if os.path.exists(icon_path):
            add_background_to_icon(icon_path)
        else:
            print(f"⚠ 文件不存在: {icon_path}")

def process_android_icons():
    """处理Android服务端图标"""
    print("\n处理Android服务端图标...")
    
    density_dirs = [
        "mipmap-mdpi",
        "mipmap-hdpi",
        "mipmap-xhdpi",
        "mipmap-xxhdpi",
        "mipmap-xxxhdpi",
    ]
    
    base_dir = "server/android/app/src/main/res"
    
    for density_dir in density_dirs:
        icon_path = os.path.join(base_dir, density_dir, "ic_launcher.png")
        if os.path.exists(icon_path):
            add_background_to_icon(icon_path)
        else:
            print(f"⚠ 文件不存在: {icon_path}")

def process_windows_icon():
    """处理Windows客户端图标"""
    print("\n处理Windows客户端图标...")
    icon_path = "client/windows/runner/resources/app_icon.ico"
    
    if not os.path.exists(icon_path):
        print(f"⚠ 文件不存在: {icon_path}")
        return
    
    try:
        # ICO文件可能包含多个尺寸，需要分别处理
        icon = Image.open(icon_path)
        
        # 创建临时目录
        temp_dir = "temp_icon"
        os.makedirs(temp_dir, exist_ok=True)
        
        # 提取所有尺寸
        sizes = []
        icon.seek(0)
        frame = 0
        while True:
            try:
                sizes.append(icon.size)
                frame += 1
                icon.seek(frame)
            except EOFError:
                break
        
        # 处理每个尺寸
        processed_images = []
        for i in range(len(sizes)):
            icon.seek(i)
            # 转换为RGBA以确保透明度处理正确
            frame_img = icon.copy().convert('RGBA')
            
            # 创建临时PNG文件
            temp_path = os.path.join(temp_dir, f"icon_{sizes[i][0]}.png")
            frame_img.save(temp_path, 'PNG')
            
            # 添加背景
            add_background_to_icon(temp_path, temp_path)
            
            # 重新加载处理后的图像
            processed_images.append(Image.open(temp_path))
        
        # 创建新的ICO文件，包含所有尺寸
        if processed_images:
            # 备份原文件
            backup_path = icon_path + ".backup"
            if not os.path.exists(backup_path):
                shutil.copy2(icon_path, backup_path)
            
            # 保存为ICO格式，包含所有尺寸
            processed_images[0].save(
                icon_path,
                format='ICO',
                sizes=[(img.size[0], img.size[1]) for img in processed_images]
            )
            print(f"✓ 已处理: {icon_path} (包含 {len(processed_images)} 个尺寸)")
        
        # 清理临时文件
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
        
    except Exception as e:
        print(f"✗ 处理失败 {icon_path}: {e}")
        import traceback
        traceback.print_exc()

def main():
    """主函数"""
    print("=" * 50)
    print("开始为应用图标添加背景")
    print("=" * 50)
    
    # 检查工作目录
    if not os.path.exists("client") or not os.path.exists("server"):
        print("错误: 请在项目根目录运行此脚本")
        sys.exit(1)
    
    # 处理各个平台的图标
    process_mac_icons()
    process_android_icons()
    process_windows_icon()
    
    print("\n" + "=" * 50)
    print("图标处理完成！")
    print("=" * 50)

if __name__ == "__main__":
    main()

