@echo off
setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

goto after_help
:print_help

echo Usage: %0 [options]
echo:
echo   Prepares the environment to be built by downloading Private.SourceBuilt.Artifacts.*.tar.gz and
echo   installing the version of dotnet referenced in global.json
echo:
echo Options:
echo   --no-artifacts              Exclude the download of the previously source-built artifacts archive
echo   --no-bootstrap              Don't replace portable packages in the download source-built artifacts
echo   --no-prebuilts              Exclude the download of the prebuilts archive
echo   --no-sdk                    Exclude the download of the .NET SDK
echo   --runtime-source-feed       URL of a remote server or a local directory, from which SDKs and
echo                               runtimes can be downloaded
echo   --runtime-source-feed-key   Key for accessing the above server, if necessary

exit /b 0
:after_help

set SCRIPT_ROOT=%~dp0

set buildBootstrap=true
set downloadArtifacts=true
set downloadPrebuilts=true
set installDotnet=true
set runtime_source_feed='' # IBM requested these to support s390x scenarios
set runtime_source_feed_key='' # IBM requested these to support s390x scenarios

:startParamLoop
if %1.==. goto doneParams

if /I "%1" EQU "--no-artifacts" (
  set downloadArtifacts=false
) else if /I "%1" EQU "--no-bootstrap" (
  set buildBootstrap=false
) else if /I "%1" EQU "--no-prebuilts" (
  set downloadPrebuilts=false
) else if /I "%1" EQU "--no-sdk" (
  set installDotnet=false
) else if /I "%1" EQU "--runtime-source-feed" (
  set runtime_source_feed=%2
  shift
) else if /I "%1" EQU "--runtime-source-feed-key" (
  set runtime_source_feed_key=%2
  shift
) else if /I "%1" EQU "--help" (
  goto print_help
) else if /I "%1" EQU "-?" (
  goto print_help
) else if /I "%1" EQU "-h" (
  goto print_help
) else (
  echo Unrecognized argument '%1'
  goto print_help
)
shift
goto startParamLoop
:doneParams

rem Attempting to bootstrap without an SDK will fail. So either the --no-sdk flag must be passed
rem or a pre-existing .dotnet SDK directory must exist.
if "!buildBootstrap!" EQU "true" (
  if "$installDotnet" NEQ "true" (
    if NOT EXIST "!SCRIPT_ROOT!.dotnet" (
      echo ERROR: --no-sdk requires --no-bootstrap or a pre-existing .dotnet SDK directory.  Exiting...
      exit /b 1
    )
  )
)

rem Check if Private.SourceBuilt artifacts archive exists
set artifactsBaseFileName=Private.SourceBuilt.Artifacts
set packagesArchiveDir=!SCRIPT_ROOT!prereqs\packages\archive\
if "!downloadArtifacts!" EQU "true" (
  if EXIST "!packagesArchiveDir!!artifactsBaseFileName!.*.tar.gz" (
    echo   !packagesArchiveDir!!artifactsBaseFileName!.*.tar.gz exists...it will not be downloaded or bootstrapped
    set downloadArtifacts=false
  )
)

rem Check if Private.SourceBuilt prebuilts archive exists
set prebuiltsBaseFileName=Private.SourceBuilt.Prebuilts
if "!downloadPrebuilts!" EQU "true" (
  if EXIST "!packagesArchiveDir!!prebuiltsBaseFileName!.*.tar.gz" (
    echo   !packagesArchiveDir!!prebuiltsBaseFileName!.*.tar.gz exists...it will not be downloaded
    set downloadPrebuilts=false
  )
)

rem Check if dotnet is installed
if "!installDotnet!" == "true" (
  if EXIST "!SCRIPT_ROOT!.dotnet" (
    echo   ./.dotnet SDK directory exists...it will not be installed
    set installDotnet=false
  )
)

rem Check for the version of dotnet to install
if "!installDotnet!" == "true" (
  echo   Installing dotnet...

  rem Set DOTNET_INSTALL_DIR to ensure that the SDK is always installed locally. The VMR will modify the install of the SDK, and cannot be allowed to affect a globally installed SDK
  set DOTNET_INSTALL_DIR=%~dp0.dotnet
  powershell -ExecutionPolicy ByPass -NoProfile -Command "& { . '%~dp0eng\common\tools.ps1'; InitializeDotNetCli $true $true }"
)

rem Read the eng/Versions.props to get the archives to download and download them
if "!downloadArtifacts!" EQU "true" (
  call :DownloadArchive Artifacts true
  if ERRORLEVEL 1 (
    exit /b 1
  )
  if "!buildBootstrap!" EQU "true" (
      call :BootstrapArtifacts
  )
)

if "!downloadPrebuilts!" EQU "true" (
  call :DownloadArchive Prebuilts false
)

goto :EOF

rem Start BootstrapArtifacts function
:BootstrapArtifacts

set DOTNET_SDK_PATH=!SCRIPT_ROOT!.dotnet

rem Create working directory for running bootstrap project
set workingDir=!SCRIPT_ROOT!artifacts\bootstrapTemp
md !workingDir!
echo   Building bootstrap previously source-built in !workingDir!

rem Copy bootstrap project to working dir
copy !SCRIPT_ROOT!eng\bootstrap\buildBootstrapPreviouslySB.csproj !workingDir!

rem Copy NuGet.config from the installer repo to have the right feeds
copy !SCRIPT_ROOT!src\installer\NuGet.config !workingDir!

rem Get PackageVersions.props from existing prev-sb archive
echo   Retrieving PackageVersions.props from existing archive
FOR /F %%a IN ('dir /s /b !packagesArchiveDir!\Private.SourceBuilt.Artifacts*.tar.gz') do (
  set sourceBuiltArchive=%%a
)
tar -xzf "!sourceBuiltArchive!" -C !workingDir! PackageVersions.props

rem Run restore on project to initiate download of bootstrap packages
"!DOTNET_SDK_PATH!\dotnet" restore !workingDir!/buildBootstrapPreviouslySB.csproj /bl:artifacts/prep/bootstrap.binlog /fileLoggerParameters:LogFile=artifacts/prep/bootstrap.log "/p:ArchiveDir=!packagesArchiveDir!" "/p:BootstrapOverrideVersionsProps=!SCRIPT_ROOT!eng\bootstrap\OverrideBootstrapVersions.props"

rem Remove working directory
rd /s /q !workingDir!

rem End function
goto :EOF

rem Start DownloadArchive function
:DownloadArchive

set archiveType=%1
set isRequired=%2

set packageVersionsPath=!SCRIPT_ROOT!eng\Versions.props
set notFoundMessage=No source-built !archiveType! found to download...

echo Looking for source-built !archiveType! to download...

set archiveUrl=
FOR /F %%a IN ('powershell -c "type !packageVersionsPath! | Select-String 'PrivateSourceBuilt!archiveType!Url>(.*)</PrivateSourceBuilt!archiveType!Url' | ForEach-Object -MemberName Matches | ForEach-Object { $_.Groups.Groups[1].Value }"') DO (
  set archiveUrl=%%a
)

if "!archiveUrl!" EQU "" (
  if "!isRequired!" EQU "true" (
    echo ERROR: !notFoundMessage!
    exit /b 1
  ) else (
    echo !notFoundMessage!
  )
) else (
  echo   Downloading source-built !archiveType! from !archiveUrl!...
  pushd !packagesArchiveDir!
  curl --retry 5 -O !archiveUrl!
  popd
)
rem End function
goto :EOF
