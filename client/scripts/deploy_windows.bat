@echo off
REM 主控端 Windows 部署脚本

echo ========================================
echo 开始构建主控端 Windows 应用
echo ========================================

cd /d "%~dp0\.."

REM 检查Flutter是否可用
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo 错误: 未找到 Flutter 命令
    echo 请确保 Flutter 已安装并添加到 PATH
    exit /b 1
)

REM 构建 Windows 应用
echo 正在构建...
flutter build windows --debug

set BUILD_PATH=build\windows\runner\Debug

if exist "%BUILD_PATH%" (
    echo ========================================
    echo 构建成功！
    echo 应用位置: %BUILD_PATH%
    echo ========================================
    
    REM 询问是否启动应用
    set /p choice="是否启动应用? (y/n) "
    if /i "%choice%"=="y" (
        start "" "%BUILD_PATH%\remote_cam_client.exe"
    )
) else (
    echo 构建失败，请检查错误信息
    exit /b 1
)

