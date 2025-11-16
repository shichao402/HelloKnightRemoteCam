#!/usr/bin/env python3
"""
从git历史恢复macOS原始图标，并将macOS图标应用到所有平台
"""

import os
import sys
import subprocess
from PIL import Image
import shutil

def restore_macos_icons():
    """从git历史恢复macOS原始图标"""
    print("\n恢复macOS原始图标...")
    
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
        try:
            # 从git历史恢复
            result = subprocess.run(
                ["git", "show", f"HEAD:{icon_path}"],
                capture_output=True,
                check=True
            )
            with open(icon_path, 'wb') as f:
                f.write(result.stdout)
            print(f"✓ 已恢复: {icon_path}")
        except subprocess.CalledProcessError:
            print(f"⚠ 无法恢复: {icon_path}")

def resize_icon(source_path, target_size, output_path):
    """调整图标尺寸"""
    try:
        icon = Image.open(source_path)
        # 使用高质量重采样
        resized = icon.resize(target_size, Image.Resampling.LANCZOS)
        resized.save(output_path, 'PNG')
        return True
    except Exception as e:
        print(f"✗ 调整尺寸失败 {source_path} -> {output_path}: {e}")
        return False

def apply_macos_to_android():
    """将macOS图标应用到Android平台"""
    print("\n将macOS图标应用到Android平台...")
    
    # 使用1024px的macOS图标作为源
    source_icon = "client/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
    
    if not os.path.exists(source_icon):
        print(f"✗ 源图标不存在: {source_icon}")
        return
    
    # Android图标尺寸映射（密度 -> 尺寸）
    android_sizes = {
        "mipmap-mdpi": (48, 48),      # 1x
        "mipmap-hdpi": (72, 72),      # 1.5x
        "mipmap-xhdpi": (96, 96),     # 2x
        "mipmap-xxhdpi": (144, 144),  # 3x
        "mipmap-xxxhdpi": (192, 192), # 4x
    }
    
    base_dir = "server/android/app/src/main/res"
    
    for density_dir, size in android_sizes.items():
        target_path = os.path.join(base_dir, density_dir, "ic_launcher.png")
        if resize_icon(source_icon, size, target_path):
            print(f"✓ 已创建: {target_path} ({size[0]}x{size[1]})")

def apply_macos_to_windows():
    """将macOS图标应用到Windows平台"""
    print("\n将macOS图标应用到Windows平台...")
    
    # 使用256px的macOS图标作为源（Windows ICO通常使用256px）
    source_icon = "client/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"
    
    if not os.path.exists(source_icon):
        print(f"✗ 源图标不存在: {source_icon}")
        return
    
    try:
        # 创建临时目录
        temp_dir = "temp_icon"
        os.makedirs(temp_dir, exist_ok=True)
        
        # Windows ICO通常需要多个尺寸，我们使用256px
        icon = Image.open(source_icon)
        
        # 保存为ICO格式
        ico_path = "client/windows/runner/resources/app_icon.ico"
        
        # 备份原文件
        backup_path = ico_path + ".backup"
        if os.path.exists(ico_path) and not os.path.exists(backup_path):
            shutil.copy2(ico_path, backup_path)
        
        # 保存为ICO（ICO格式会自动处理）
        icon.save(ico_path, format='ICO', sizes=[(256, 256)])
        print(f"✓ 已创建: {ico_path}")
        
        # 清理临时文件
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
            
    except Exception as e:
        print(f"✗ 处理失败: {e}")
        import traceback
        traceback.print_exc()

def main():
    """主函数"""
    print("=" * 50)
    print("恢复macOS原始图标并应用到所有平台")
    print("=" * 50)
    
    # 检查工作目录
    if not os.path.exists("client") or not os.path.exists("server"):
        print("错误: 请在项目根目录运行此脚本")
        sys.exit(1)
    
    # 恢复macOS原始图标
    restore_macos_icons()
    
    # 应用到其他平台
    apply_macos_to_android()
    apply_macos_to_windows()
    
    print("\n" + "=" * 50)
    print("图标恢复和应用完成！")
    print("=" * 50)

if __name__ == "__main__":
    main()

