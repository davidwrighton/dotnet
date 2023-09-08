setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
echo Copy the SDK of the right version to the .dotnet directory
powershell -ExecutionPolicy ByPass -NoProfile -Command "& { . '%~dp0eng\common\tools.ps1'; InitializeDotNetCli $true $true }"
echo TODO Copy the Private.SourceBuilt.Artifacts.XXXtar.gz to the prereqs\packages\archive directory