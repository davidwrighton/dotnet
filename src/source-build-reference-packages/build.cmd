@echo off
setlocal

set DOTNET_CLI_TELEMETRY_OPTOUT=1
set DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
set DOTNET_MULTILEVEL_LOOKUP=0

set _args=%*
if "%~1"=="-?" set _args=-help

powershell -ExecutionPolicy ByPass -NoProfile -File "%~dp0eng\common\build.ps1" --build --restore --pack %_args%
exit /b %ERRORLEVEL%
