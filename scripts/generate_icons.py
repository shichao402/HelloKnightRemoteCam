#!/usr/bin/env python3
"""
图标生成脚本
为HelloKnightRemoteCam项目生成带背景的应用图标
"""

from PIL import Image, ImageDraw, ImageFont
import os
import sys
from pathlib import Path

# 颜色定义
BACKGROUND_GRADIENT_START = (30, 60, 120)  # 深蓝色
BACKGROUND_GRADIENT_END = (80, 40, 120)    # 紫色
CAMERA_COLOR = (255, 255, 255)             # 白色相机
ACCENT_COLOR = (100, 200, 255)             # 亮蓝色高光

def create_gradient_background(size, start_color, end_color):
    """创建渐变背景"""
    img = Image.new('RGB', size, start_color)
    draw = ImageDraw.Draw(img)
    
    # 创建径向渐变效果
    center_x, center_y = size[0] // 2, size[1] // 2
    max_radius = int((size[0] ** 2 + size[1] ** 2) ** 0.5)
    
    for y in range(size[1]):
        for x in range(size[0]):
            # 计算到中心的距离
            dx = x - center_x
            dy = y - center_y
            distance = (dx ** 2 + dy ** 2) ** 0.5
            
            # 归一化距离
            ratio = min(distance / max_radius, 1.0)
            
            # 插值颜色
            r = int(start_color[0] + (end_color[0] - start_color[0]) * ratio)
            g = int(start_color[1] + (end_color[1] - start_color[1]) * ratio)
            b = int(start_color[2] + (end_color[2] - start_color[2]) * ratio)
            
            img.putpixel((x, y), (r, g, b))
    
    return img

def draw_camera_icon(draw, size, center_x, center_y, scale):
    """绘制相机图标"""
    # 相机主体（圆角矩形）
    body_width = int(60 * scale)
    body_height = int(45 * scale)
    body_x = center_x - body_width // 2
    body_y = center_y - body_height // 2
    
    # 绘制相机主体
    body_coords = [
        (body_x, body_y + int(10 * scale)),  # 左上角（圆角）
        (body_x + body_width, body_y + int(10 * scale)),  # 右上角
        (body_x + body_width, body_y + body_height),  # 右下角
        (body_x, body_y + body_height),  # 左下角
    ]
    draw.rounded_rectangle(
        [body_x, body_y + int(10 * scale), body_x + body_width, body_y + body_height],
        radius=int(8 * scale),
        fill=CAMERA_COLOR,
        outline=None,
        width=0
    )
    
    # 相机镜头（圆形）
    lens_radius = int(18 * scale)
    lens_x = center_x
    lens_y = center_y + int(5 * scale)
    
    # 外圈
    draw.ellipse(
        [lens_x - lens_radius, lens_y - lens_radius,
         lens_x + lens_radius, lens_y + lens_radius],
        fill=(40, 40, 40),
        outline=None
    )
    
    # 内圈（高光）
    inner_radius = int(12 * scale)
    draw.ellipse(
        [lens_x - inner_radius, lens_y - inner_radius,
         lens_x + inner_radius, lens_y + inner_radius],
        fill=(60, 60, 80),
        outline=None
    )
    
    # 镜头中心高光
    highlight_radius = int(4 * scale)
    draw.ellipse(
        [lens_x - highlight_radius, lens_y - highlight_radius,
         lens_x + highlight_radius, lens_y + highlight_radius],
        fill=ACCENT_COLOR,
        outline=None
    )
    
    # 闪光灯（小圆点）
    flash_x = center_x + int(20 * scale)
    flash_y = center_y - int(8 * scale)
    flash_radius = int(4 * scale)
    draw.ellipse(
        [flash_x - flash_radius, flash_y - flash_radius,
         flash_x + flash_radius, flash_y + flash_radius],
        fill=ACCENT_COLOR,
        outline=None
    )
    
    # 顶部装饰线（表示远程连接）
    top_y = body_y + int(5 * scale)
    line_width = int(2 * scale)
    draw.line(
        [body_x + int(15 * scale), top_y,
         body_x + body_width - int(15 * scale), top_y],
        fill=ACCENT_COLOR,
        width=line_width
    )

def generate_icon(size, output_path):
    """生成单个尺寸的图标"""
    # 创建带透明通道的图像
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # 创建渐变背景
    bg = create_gradient_background((size, size), BACKGROUND_GRADIENT_START, BACKGROUND_GRADIENT_END)
    
    # 将背景转换为RGBA并应用圆角
    bg_rgba = bg.convert('RGBA')
    
    # 创建圆角遮罩
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    corner_radius = int(size * 0.2)  # 20%圆角
    mask_draw.rounded_rectangle(
        [0, 0, size, size],
        radius=corner_radius,
        fill=255
    )
    
    # 应用圆角
    bg_rgba.putalpha(mask)
    
    # 合成背景
    img = Image.alpha_composite(img, bg_rgba)
    
    # 绘制相机图标
    draw = ImageDraw.Draw(img)
    scale = size / 1024.0  # 基于1024px设计
    draw_camera_icon(draw, size, size // 2, size // 2, scale)
    
    # 保存
    img.save(output_path, 'PNG', optimize=True)
    print(f"✓ 生成图标: {output_path} ({size}x{size})")

def generate_macos_icons():
    """生成macOS客户端图标"""
    base_dir = Path(__file__).parent.parent / 'client' / 'macos' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    base_dir.mkdir(parents=True, exist_ok=True)
    
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    
    for size in sizes:
        output_path = base_dir / f'app_icon_{size}.png'
        generate_icon(size, output_path)
    
    print(f"\n✓ macOS图标生成完成: {base_dir}")

def generate_windows_icon():
    """生成Windows客户端图标（ICO格式，包含多个尺寸）"""
    base_dir = Path(__file__).parent.parent / 'client' / 'windows' / 'runner' / 'resources'
    base_dir.mkdir(parents=True, exist_ok=True)
    
    # ICO文件需要包含多个尺寸
    sizes = [16, 32, 48, 64, 128, 256]
    images = []
    
    for size in sizes:
        img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        
        # 创建渐变背景
        bg = create_gradient_background((size, size), BACKGROUND_GRADIENT_START, BACKGROUND_GRADIENT_END)
        bg_rgba = bg.convert('RGBA')
        
        # 创建圆角遮罩
        mask = Image.new('L', (size, size), 0)
        mask_draw = ImageDraw.Draw(mask)
        corner_radius = int(size * 0.2)
        mask_draw.rounded_rectangle(
            [0, 0, size, size],
            radius=corner_radius,
            fill=255
        )
        bg_rgba.putalpha(mask)
        
        # 合成背景
        img = Image.alpha_composite(img, bg_rgba)
        
        # 绘制相机图标
        draw = ImageDraw.Draw(img)
        scale = size / 1024.0
        draw_camera_icon(draw, size, size // 2, size // 2, scale)
        
        images.append(img)
    
    # 保存为ICO文件
    output_path = base_dir / 'app_icon.ico'
    images[0].save(
        output_path,
        format='ICO',
        sizes=[(img.width, img.height) for img in images]
    )
    print(f"\n✓ Windows图标生成完成: {output_path}")

def generate_android_icons():
    """生成Android服务端图标（多个密度）"""
    base_dir = Path(__file__).parent.parent / 'server' / 'android' / 'app' / 'src' / 'main' / 'res'
    
    # Android密度映射
    densities = {
        'mipmap-mdpi': 48,      # 1x
        'mipmap-hdpi': 72,      # 1.5x
        'mipmap-xhdpi': 96,     # 2x
        'mipmap-xxhdpi': 144,   # 3x
        'mipmap-xxxhdpi': 192,  # 4x
    }
    
    for density, size in densities.items():
        density_dir = base_dir / density
        density_dir.mkdir(parents=True, exist_ok=True)
        
        output_path = density_dir / 'ic_launcher.png'
        generate_icon(size, output_path)
    
    print(f"\n✓ Android图标生成完成: {base_dir}")

def main():
    """主函数"""
    print("开始生成应用图标...\n")
    
    try:
        # 生成macOS图标
        print("=" * 50)
        print("生成macOS客户端图标")
        print("=" * 50)
        generate_macos_icons()
        
        # 生成Windows图标
        print("\n" + "=" * 50)
        print("生成Windows客户端图标")
        print("=" * 50)
        generate_windows_icon()
        
        # 生成Android图标
        print("\n" + "=" * 50)
        print("生成Android服务端图标")
        print("=" * 50)
        generate_android_icons()
        
        print("\n" + "=" * 50)
        print("✓ 所有图标生成完成！")
        print("=" * 50)
        
    except Exception as e:
        print(f"\n✗ 错误: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()

