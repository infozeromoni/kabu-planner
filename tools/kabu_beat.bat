@echo off
title kabu_beat
echo Sending kabu STATION heartbeat every 60 seconds.
echo Close this window to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kabu_beat.ps1"
