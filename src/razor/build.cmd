@echo off
setlocal enabledelayedexpansion

rem Force restore and build to always be set
set EXTRAARGS=
echo %*|find "-restore"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -restore)
echo %*|find "-build"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -build)

set _args=!EXTRAARGS! %*
if "%~1"=="-?" set _args=-help

powershell -ExecutionPolicy ByPass -NoProfile -Command "& '%~dp0eng\common\build.ps1'" %_args%
exit /b %ERRORLEVEL%
