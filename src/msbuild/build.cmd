@echo off
setlocal enabledelayedexpansion

rem Force restore and build to always be set
set EXTRAARGS=
echo %*|find "-restore"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -restore)
echo %*|find "-build"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -build)

if defined MSBUILDDEBUGONSTART_HARD goto build
if not defined MSBUILDDEBUGONSTART goto build
if %MSBUILDDEBUGONSTART% == 0 goto build
set MSBUILDDEBUGONSTART=
echo To debug the build, define a value for MSBUILDDEBUGONSTART_HARD.
:build
powershell -NoLogo -NoProfile -ExecutionPolicy ByPass -Command "& """%~dp0eng\common\build.ps1""" !EXTRAARGS! %*"
exit /b %ErrorLevel%
