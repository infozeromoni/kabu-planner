@echo off
rem kabuステーションAPI → kabu-planner 保有同期（ダブルクリックで実行）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kabu_sync.ps1"
pause
