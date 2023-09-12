@echo off
setlocal enabledelayedexpansion

rem Force restore and build to always be set
set EXTRAARGS=
echo %*|find "-restore"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -restore)
echo %*|find "-build"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -build)

powershell -ExecutionPolicy ByPass -NoProfile -command "& """%~dp0eng\common\build.ps1""" !EXTRAARGS! %*"
exit /b %ERRORLEVEL%