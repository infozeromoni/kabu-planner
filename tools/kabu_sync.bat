@echo off
rem kabu STATION API -> kabu-planner holdings sync (double-click to run)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kabu_sync.ps1"
pause
