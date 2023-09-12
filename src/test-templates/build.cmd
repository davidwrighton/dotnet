@echo off
setlocal enabledelayedexpansion

rem Force restore, build and pack to always be set
set EXTRAARGS=
echo %*|find "-restore"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -restore)
echo %*|find "-build"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -build)
echo %*|find "-pack"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -pack)

powershell -ExecutionPolicy ByPass -NoProfile -command "& """%~dp0eng\common\Build.ps1""" !EXTRAARGS! %*"
exit /b %ErrorLevel%
