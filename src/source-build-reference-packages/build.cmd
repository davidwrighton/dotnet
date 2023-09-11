@echo off
setlocal enabledelayedexpansion

set DOTNET_CLI_TELEMETRY_OPTOUT=1
set DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
set DOTNET_MULTILEVEL_LOOKUP=0

set _args=%*
if "%~1"=="-?" set _args=-help

rem Force restore, build and pack to always be set

set EXTRAARGS=
echo %_args%|find "-restore"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! --restore)
echo %_args%|find "-build"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! --build)
echo %_args%|find "-pack"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! --pack)



powershell -ExecutionPolicy ByPass -NoProfile -File "%~dp0eng\common\build.ps1" %EXTRAARGS% %_args%
exit /b %ERRORLEVEL%
