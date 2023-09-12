@echo off
setlocal enabledelayedexpansion

rem Force restore to always be set
set EXTRAARGS=
echo %*|find "-restore"
if ERRORLEVEL 1 (set EXTRAARGS=!EXTRAARGS! -restore)

powershell -ExecutionPolicy ByPass -NoProfile -command "& """%~dp0eng\build.ps1""" %EXTRAARGS% %*"
exit /b %ErrorLevel%
