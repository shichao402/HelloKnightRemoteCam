#!/usr/bin/env python3
"""
为所有平台的图标添加圆角
支持 macOS、Windows 和 Android 平台
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

def process_macos_icons():
    """处理 macOS 图标"""
    print("处理 macOS 图标...")
    icon_dir = "client/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    
    if not os.path.exists(icon_dir):
        print(f"错误: {icon_dir} 不存在")
        return False
    
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
    
    for icon_file in icon_files:
        icon_path = os.path.join(icon_dir, icon_file)
        if not os.path.exists(icon_path):
            print(f"警告: {icon_path} 不存在，跳过")
            continue
        
        try:
            # 打开图像
            img = Image.open(icon_path).convert('RGBA')
            width, height = img.size
            
            # 计算圆角半径（约为图像尺寸的 20%，但不超过 80 像素）
            corner_radius = min(int(width * 0.2), 80)
            
            # 添加圆角
            rounded_img = add_rounded_corners(img, corner_radius)
            
            # 保存
            rounded_img.save(icon_path, 'PNG', optimize=True)
            print(f"✓ 已处理: {icon_file} ({width}x{height}, 圆角半径: {corner_radius}px)")
        except Exception as e:
            print(f"错误: 处理 {icon_file} 时出错: {e}")
            return False
    
    return True

def process_windows_icon():
    """处理 Windows 图标"""
    print("处理 Windows 图标...")
    icon_path = "client/windows/runner/resources/app_icon.ico"
    
    # 优先使用macOS的高分辨率图标作为源
    mac_icon_1024 = "client/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
    
    source_img = None
    source_path = None
    
    # 尝试从macOS 1024x1024图标获取
    if os.path.exists(mac_icon_1024):
        try:
            source_img = Image.open(mac_icon_1024).convert('RGBA')
            source_path = mac_icon_1024
            print(f"  使用源图标: {mac_icon_1024} ({source_img.size[0]}x{source_img.size[1]})")
        except:
            pass
    
    # 如果没有macOS图标，尝试使用现有的ICO或PNG
    if source_img is None:
        png_path = icon_path.replace('.ico', '.png')
        if os.path.exists(png_path):
            try:
                source_img = Image.open(png_path).convert('RGBA')
                source_path = png_path
                print(f"  使用源图标: {png_path} ({source_img.size[0]}x{source_img.size[1]})")
            except:
                pass
    
    if source_img is None:
        if os.path.exists(icon_path):
            try:
                source_img = Image.open(icon_path).convert('RGBA')
                source_path = icon_path
                print(f"  使用源图标: {icon_path} ({source_img.size[0]}x{source_img.size[1]})")
            except Exception as e:
                print(f"错误: 无法打开任何源图标文件: {e}")
                return False
        else:
            print(f"错误: 找不到图标源文件")
            return False
    
    try:
        # Windows ICO 标准尺寸（从大到小）
        ico_sizes = [256, 128, 64, 48, 32, 16]
        
        # 确保源图像是方形的
        width, height = source_img.size
        if width != height:
            # 裁剪为正方形（居中）
            size = min(width, height)
            left = (width - size) // 2
            top = (height - size) // 2
            source_img = source_img.crop((left, top, left + size, top + size))
            width = height = size
        
        # 为源图像添加圆角（使用较大的圆角半径，因为这是高分辨率图像）
        corner_radius = min(int(width * 0.2), 80)
        rounded_source = add_rounded_corners(source_img, corner_radius)
        
        # 生成所有尺寸的圆角图标
        rounded_images = []
        for size in ico_sizes:
            if size <= width:
                resized = rounded_source.resize((size, size), Image.Resampling.LANCZOS)
                rounded_images.append(resized)
        
        # 如果没有生成任何尺寸，至少保存原始尺寸
        if not rounded_images:
            # 如果源图像太大，至少生成256x256
            if width > 256:
                rounded_images.append(rounded_source.resize((256, 256), Image.Resampling.LANCZOS))
            else:
                rounded_images.append(rounded_source)
        
        # 保存为ICO（PIL的ICO保存可能只支持单尺寸，所以我们保存最大的）
        # 但我们可以尝试保存多个尺寸
        try:
            # 尝试保存多尺寸ICO
            rounded_images[0].save(
                icon_path,
                format='ICO',
                sizes=[(img.size[0], img.size[1]) for img in rounded_images] if len(rounded_images) > 1 else None
            )
        except:
            # 如果失败，只保存最大尺寸
            rounded_images[0].save(icon_path, format='ICO')
        
        print(f"✓ 已处理: app_icon.ico ({len(rounded_images)} 个尺寸, 最大: {rounded_images[0].size[0]}x{rounded_images[0].size[1]})")
        
        # 清理临时PNG文件（如果存在且不是源文件）
        png_path = icon_path.replace('.ico', '.png')
        if os.path.exists(png_path) and png_path != source_path:
            os.remove(png_path)
            print(f"  已清理临时PNG文件: {png_path}")
        
        return True
    except Exception as e:
        print(f"错误: 处理 Windows 图标时出错: {e}")
        import traceback
        traceback.print_exc()
        return False

def process_android_icons():
    """处理 Android 图标"""
    print("处理 Android 图标...")
    base_dir = "server/android/app/src/main/res"
    
    # Android 使用自适应图标，需要处理 foreground 和 background
    mipmap_dirs = [
        "mipmap-hdpi",
        "mipmap-mdpi",
        "mipmap-xhdpi",
        "mipmap-xxhdpi",
        "mipmap-xxxhdpi",
    ]
    
    # 处理 foreground 图标（前景图标）
    for mipmap_dir in mipmap_dirs:
        res_dir = os.path.join(base_dir, mipmap_dir)
        if not os.path.exists(res_dir):
            continue
        
        foreground_path = os.path.join(res_dir, "ic_launcher_foreground.png")
        if os.path.exists(foreground_path):
            try:
                img = Image.open(foreground_path).convert('RGBA')
                width, height = img.size
                corner_radius = min(int(width * 0.2), 80)
                rounded_img = add_rounded_corners(img, corner_radius)
                rounded_img.save(foreground_path, 'PNG', optimize=True)
                print(f"✓ 已处理: {mipmap_dir}/ic_launcher_foreground.png ({width}x{height})")
            except Exception as e:
                print(f"错误: 处理 {foreground_path} 时出错: {e}")
        
        # 也处理传统的 ic_launcher.png（如果存在）
        launcher_path = os.path.join(res_dir, "ic_launcher.png")
        if os.path.exists(launcher_path):
            try:
                img = Image.open(launcher_path).convert('RGBA')
                width, height = img.size
                corner_radius = min(int(width * 0.2), 80)
                rounded_img = add_rounded_corners(img, corner_radius)
                rounded_img.save(launcher_path, 'PNG', optimize=True)
                print(f"✓ 已处理: {mipmap_dir}/ic_launcher.png ({width}x{height})")
            except Exception as e:
                print(f"错误: 处理 {launcher_path} 时出错: {e}")
    
    return True

def main():
    """主函数"""
    print("=" * 60)
    print("图标圆角处理脚本")
    print("=" * 60)
    print()
    
    # 切换到项目根目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    os.chdir(project_root)
    
    print(f"工作目录: {os.getcwd()}")
    print()
    
    success = True
    
    # 处理 macOS 图标
    if not process_macos_icons():
        success = False
    print()
    
    # 处理 Windows 图标
    if not process_windows_icon():
        success = False
    print()
    
    # 处理 Android 图标
    if not process_android_icons():
        success = False
    print()
    
    if success:
        print("=" * 60)
        print("✓ 所有图标处理完成！")
        print("=" * 60)
        return 0
    else:
        print("=" * 60)
        print("✗ 部分图标处理失败，请检查错误信息")
        print("=" * 60)
        return 1

if __name__ == "__main__":
    sys.exit(main())

