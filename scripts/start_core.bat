@echo off
REM Core Service 开发启动脚本（Windows）
set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%..\core"

if not exist "node_modules" (
  echo Installing dependencies...
  call npm install
)

echo Starting Core Service in dev mode...
npx tsx watch src/main.ts
