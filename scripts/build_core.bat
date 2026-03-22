@echo off
REM Core Service 构建脚本（Windows）
set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%..\core"

echo === Core Service: Install Dependencies ===
call npm install

echo.
echo === Core Service: Run Tests ===
call npx vitest run

echo.
echo === Core Service: Build ===
call npx tsc

echo.
echo === Core Service: Build Complete ===
echo Start with: cd core ^&^& npm run dev
