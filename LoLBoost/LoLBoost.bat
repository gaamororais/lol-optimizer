@echo off
title LoLBoost
cd /d "%~dp0"

:: auto-elevar
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0LoLBoost.ps1"
