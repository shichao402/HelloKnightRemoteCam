@echo off
REM 主控端 Windows 部署脚本（向后兼容包装器）
REM 此脚本调用新的模块化部署脚本

setlocal

cd /d "%~dp0\.."

REM 检查是否有 Git Bash 或 WSL
where bash >nul 2>nul
if %errorlevel% equ 0 (
    REM 使用 bash 调用新的部署脚本
    bash scripts/deploy.sh --debug --windows
    exit /b %errorlevel%
)

REM 如果没有 bash，尝试使用 WSL
where wsl >nul 2>nul
if %errorlevel% equ 0 (
    wsl bash scripts/deploy.sh --debug --windows
    exit /b %errorlevel%
)

REM 如果都没有，提示用户
echo 错误: 未找到 bash 或 wsl 命令
echo 请安装 Git for Windows 或 WSL 以使用新的模块化脚本
echo.
echo 或者使用旧的方式（需要手动构建）:
echo   flutter build windows --debug
echo   flutter run -d windows
exit /b 1
