@echo off
setlocal enableextensions enabledelayedexpansion

goto after_help
:print_help

echo Usage: %0 [options]
echo:
echo Options:
echo   --clean-while-building       Cleans each repo after building (reduces disk space usage)
echo   --online                     Build using online sources
echo   --poison                     Build with poisoning checks
echo   --run-smoke-test             Don't build; run smoke tests
echo   --source-repository <URL>    Source Link repository URL, required when building from tarball
echo   --source-version <SHA>       Source Link revision, required when building from tarball
echo   --release-manifest <FILE>    A JSON file, an alternative source of Source Link metadata
echo   --use-mono-runtime           Output uses the mono runtime
echo   --with-packages <DIR>        Use the specified directory of previously-built packages
echo   --with-sdk <DIR>             Use the SDK in the specified directory for bootstrapping
echo:
echo Use -- to send the remaining arguments to MSBuild

exit /b 0
:after_help

rem TODO Probably dont need this set -euo pipefail
rem TODO Don't know what this is IFS=\n\t'

set SCRIPT_ROOT=%~dp0

set MSBUILD_ARGUMENTS=-flp:v=detailed
set CUSTOM_PACKAGES_DIR=
set alternateTarget=false
set runningSmokeTests=false
set packagesDir=%SCRIPT_ROOT%prereqs\packages\
set packagesArchiveDir=%packagesDir%archive\
set packagesRestoredDir=%packagesDir%restored\
set packagesPreviouslySourceBuiltDir=%packagesDir%previously-source-built\
set CUSTOM_SDK_DIR=


set sourceRepository=
set sourceVersion=
set releaseManifest=


:startParamLoop
if %1.==. goto doneParams


if /I "%1" EQU "--clean-while-building" (
  set MSBUILD_ARGUMENTS=!MSBUILD_ARGUMENTS! -p:CleanWhileBuilding=true
) else if /I "%1" EQU "--online" (
  set MSBUILD_ARGUMENTS=!MSBUILD_ARGUMENTS! -p:BuildWithOnlineSources=true
) else if /I "%1" EQU "--poison" (
  set MSBUILD_ARGUMENTS=!MSBUILD_ARGUMENTS! -p:EnablePoison=true
) else if /I "%1" EQU "--run-smoke-test" (
  set alternateTarget=true
  set runningSmokeTests=true
  set MSBUILD_ARGUMENTS=!MSBUILD_ARGUMENTS! -t:RunSmokeTest
) else if /I "%1" EQU "--source-repository" (
  set sourceRepository=%2
  shift
) else if /I "%1" EQU "--source-version" (
  set sourceVersion=%2
  shift
) else if /I "%1" EQU "--release-manifest" (
  set releaseManifest=%2
  shift
) else if /I "%1" EQU "--use-mono-runtime" (
  set MSBUILD_ARGUMENTS=!MSBUILD_ARGUMENTS! -p:SourceBuildUseMonoRuntime=true
) else if /I "%1" EQU "--with-packages" (
  set CUSTOM_PACKAGES_DIR=%2\
  if not exist "!CUSTOM_PACKAGES_DIR!" (
    echo Custom prviously built packages directory '!CUSTOM_PACKAGES_DIR!' does not exist
    exit /b 1
  )
  shift
) else if /I "%1" EQU "--with-sdk" (
  set CUSTOM_SDK_DIR=%2\
  if not exist "!CUSTOM_SDK_DIR!" (
    echo Custom SDK directory '!CUSTOM_SDK_DIR!' does not exist
    exit /b 1
  )
  if not exist "!CUSTOM_SDK_DIR!\dotnet.exe" (
    echo Custom SDK '!CUSTOM_SDK_DIR!\dotnet.exe' does not exist or is not executable
    exit /b 1
  )
  shift
) else if /I "%1" EQU "--" (
  shift
  echo "Detected '--': passing remaining parameters '%*' as build.sh arguments."
  goto doneParams
) else if /I "%1" EQU "--help" (
  goto print_help
) else if /I "%1" EQU "-h" (
  goto print_help
) else if /I "%1" EQU "-?" (
  goto print_help
) else (
  echo Unrecognized argument '%1'
  goto print_help
)
shift
goto startParamLoop
:doneParams

rem For build purposes, we need to make sure we have all the SourceLink information
if /I "$alternateTarget" NEQ "true"  (
  set GIT_DIR=!SCRIPT_ROOT!\.git"
  if exist "!GIT_DIR!\index" (
rem We check for index because if outside of git, we create config and HEAD manually
    if "!sourceRepository!!sourceVersion!!releaseManifest!" NEQ "" (
      echo ERROR: Source Link arguments cannot be used in a git repository
      exit /b 1
    )
  ) else (
    if "!releaseManifest!" EQU "" (
      if "!sourceRepository!" EQU "" (
        echo "ERROR: !SCRIPT_ROOT! is not a git repository, either --release-manifest or --source-repository and --source-version must be specified"
        exit /b 1
      )
      if "!sourceVersion!" EQU "" (
        echo "ERROR: !SCRIPT_ROOT! is not a git repository, either --release-manifest or --source-repository and --source-version must be specified"
        exit /b 1
      )
    ) else (
      if "!sourceRepository!!sourceVersion!" NEQ "" (
        echo "ERROR: --release-manifest cannot be specified together with --source-repository and --source-version"
        exit /b 1
      )

rem TODO Implement this get_property stuff
rem      get_property() {
rem        local json_file_path="$1"
rem        local property_name="$2"
rem        grep -oP '(?<="'$property_name'": ")[^"]*' "$json_file_path"
rem      }

rem      sourceRepository=$(get_property "$releaseManifest" sourceRepository) \
rem         || (echo "ERROR: Failed to find sourceRepository in $releaseManifest" && exit /b 1)
rem       sourceVersion=$(get_property "$releaseManifest" sourceVersion) \
rem         || (echo "ERROR: Failed to find sourceVersion in $releaseManifest" && exit /b 1)

rem       if [ -z "$sourceRepository" ] || [ -z "$sourceVersion" ]; then
rem        echo "ERROR: sourceRepository and sourceVersion must be specified in $releaseManifest"
rem        exit /b 1
rem      fi
    )

    rem We need to add "fake" .git/ files when not building from a git repository
    md !GIT_DIR!
    echo '[remote "origin"]' > "!GIT_DIR!/config"
    echo url=""$sourceRepository"" >> "!GIT_DIR!/config"
    echo $sourceVersion > "!GIT_DIR!/HEAD"
  )
)

if "!CUSTOM_PACKAGES_DIR!" NEQ "" ] (
  if /I "!runningSmokeTests!" EQU "true" (
    set MSBUILD_ARGUMENTS=!MSBUILD_ARGUMENTS! -p:CustomSourceBuiltPackagesPath=!CUSTOM_PACKAGES_DIR!
  else
    set MSBUILD_ARGUMENTS=!MSBUILD_ARGUMENTS! -p:CustomPrebuiltSourceBuiltPackagesPath=!CUSTOM_PACKAGES_DIR!
  fi
)

set BUILD_LOCAL_SDK=
if EXIST "!SCRIPT_ROOT!artifacts\toolset\sdk.txt" (
  set /p BUILD_LOCAL_SDK=<!SCRIPT_ROOT!artifacts\toolset\sdk.txt
)

if exist "!packagesArchiveDir!archiveArtifacts.txt" (
  set ARCHIVE_ERROR=0
  if NOT EXIST "!BUILD_LOCAL_SDK!"  (
    if "!CUSTOM_SDK_DIR!" EQU "" (
      echo "ERROR: SDK not found at '!BUILD_LOCAL_SDK|'. Either run prep.cmd to acquire one or specify one via the --with-sdk parameter."
      set ARCHIVE_ERROR=1
    )
  )
  if NOT EXIST "!packagesArchiveDir!Private.SourceBuilt.Artifacts*.tar.gz" (
    if "!CUSTOM_PACKAGES_DIR!" EQU "" (
      echo "ERROR: Private.SourceBuilt.Artifacts artifact not found at '!packagesArchiveDir!'. Either run prep.cmd to acquire it or specify one via the --with-packages parameter."
      set ARCHIVE_ERROR=1
    )
  )
  if "!ARCHIVE_ERROR!" EQU "1" (
    exit /b 1
  )
)

if NOT EXIST "!SCRIPT_ROOT!\.git" (
  echo "ERROR: !SCRIPT_ROOT! is not a git repository. Please run prep.cmd add initialize Source Link metadata."
  exit /b 1
)

if EXIST "!CUSTOM_SDK_DIR!" (
  FOR /F %%a IN ('"!CUSTOM_SDK_DIR!\dotnet" --version') DO (
    set SDK_VERSION=%%a
  )
  set CLI_ROOT=!CUSTOM_SDK_DIR!
  set _InitializeDotNetCli=!CLI_ROOT!\dotnet
  set CustomDotNetSdkDir=!CLI_ROOT!
  echo Using custom bootstrap SDK from "!CLI_ROOT!", version "!SDK_VERSION!"
) else (
  FOR /F %%a IN ('powershell -c "type !SCRIPT_ROOT!\global.json | Select-String ""`\""dotnet`\"" *: *`\""(.*)`\"""" | ForEach-Object -MemberName Matches | ForEach-Object { $_.Groups.Groups[1].Value } "') DO (
    set SDK_VERSION=%%a
    set CLI_ROOT=!BUILD_LOCAL_SDK!
  )
  set VALID_SDK_VERSION_FOUND=
  FOR /F %%a IN ('"!CLI_ROOT!\dotnet" --list-sdks ^| findstr !SDK_VERSION!') DO (
    set VALID_SDK_VERSION_FOUND=1
  )
  if "!VALID_SDK_VERSION_FOUND!" NEQ "1" (
    echo ERROR sdk located at !CLI_ROOT! does not include SDK_VERSION !SDK_VERSION!
    exit /b 1
  )
)

set packageVersionsPath=

if "!CUSTOM_PACKAGES_DIR!" NEQ "" (
  if EXIST !CUSTOM_PACKAGES_DIR!\PackageVersions.props (
    set packageVersionsPath=!CUSTOM_PACKAGES_DIR!\PackageVersions.props
  )
)

if "!packageVersionsPath!" EQU "" (
  if EXIST "!packagesArchiveDir!" (
    FOR /F %%a IN ('dir /s /b !packagesArchiveDir!\Private.SourceBuilt.Artifacts*.tar.gz') do (
      set sourceBuiltArchive=%%a
    )

    if EXIST "!packagesPreviouslySourceBuiltDir!PackageVersions.props" (
      set packageVersionsPath=!packagesPreviouslySourceBuiltDir!PackageVersions.props
    ) else (
      if EXIST "!sourceBuiltArchive!" (
        tar -xzf "!sourceBuiltArchive!" -C %TEMP% PackageVersions.props
        set packageVersionsPath=%TEMP%\PackageVersions.props
      )
    )
  )
)

if not exist "!packageVersionsPath!" (
  echo "Cannot find PackagesVersions.props.  Debugging info:"
  echo "  Attempted archive path: !packagesArchiveDir!"
  echo "  Attempted custom PVP path: !CUSTOM_PACKAGES_DIR!/PackageVersions.props"
  exit /b 1
)

FOR /F %%a IN ('powershell -c "type !packageVersionsPath! | Select-String 'MicrosoftDotNetArcadeSdkVersion>(.*)</MicrosoftDotNetArcadeSdkVersion' | ForEach-Object -MemberName Matches | ForEach-Object { $_.Groups.Groups[1].Value }"') DO (
  set ARCADE_BOOTSTRAP_VERSION=%%a

  rem Ensure that by default, the bootstrap version of the Arcade SDK is used. Source-build infra
  rem projects use bootstrap Arcade SDK, and would fail to find it in the build. The repo
  rem projects overwrite this so that they use the source-built Arcade SDK instad.
  set SOURCE_BUILT_SDK_ID_ARCADE=Microsoft.DotNet.Arcade.Sdk
  set SOURCE_BUILT_SDK_VERSION_ARCADE=!ARCADE_BOOTSTRAP_VERSION!
  set SOURCE_BUILT_SDK_DIR_ARCADE=!packagesRestoredDir!\ArcadeBootstrapPackage\microsoft.dotnet.arcade.sdk\!ARCADE_BOOTSTRAP_VERSION!
)

FOR /F %%a IN ('powershell -c "type !packageVersionsPath! | Select-String 'MicrosoftSourceLinkCommonVersion>(.*)</MicrosoftSourceLinkCommonVersion' | ForEach-Object -MemberName Matches | ForEach-Object { $_.Groups.Groups[1].Value }"') DO (
  set SOURCE_LINK_BOOTSTRAP_VERSION=%%a
)

echo Found bootstrap SDK !SDK_VERSION!, bootstrap Arcade !ARCADE_BOOTSTRAP_VERSION!, bootstrap SourceLink !SOURCE_LINK_BOOTSTRAP_VERSION!

set DOTNET_CLI_TELEMETRY_OPTOUT=1
set NUGET_PACKAGES=!packagesRestoredDir!\

rem source $SCRIPT_ROOT/eng/common/native/init-os-and-arch.sh
rem source $SCRIPT_ROOT/eng/common/native/init-distro-rid.sh
rem initDistroRidGlobal "$os" "$arch" ""

FOR /F "skip=1 tokens=1-6" %%A IN ('WMIC Path Win32_LocalTime Get Day^,Hour^,Minute^,Month^,Second^,Year /Format:table') DO (
  SET /A FD=%%F*1000000+%%D*100+%%A
  SET /A FT=10000+%%B*100+%%C
  set FL=!FT:~-4!
  set LogDateStamp=!FD!_!FT!
)

echo CLI_ROOT=!CLI_ROOT!

call "!CLI_ROOT!\dotnet" build-server shutdown

set LogDir=!SCRIPT_ROOT!\artifacts\log\Debug
md !LogDir!

if "!alternateTarget!" EQU "true" (
  set NUGET_PACKAGES=!NUGET_PACKAGES!/smoke-tests
  call "!CLI_ROOT!\dotnet" msbuild "!SCRIPT_ROOT!\build.proj" "-bl:!SCRIPT_ROOT!\artifacts\log\Debug\BuildTests_$LogDateStamp.binlog" "-flp:LogFile=$SCRIPT_ROOT/artifacts/logs/BuildTests_!LogDateStamp!.log" -clp:v=m !MSBUILD_ARGUMENTS! %*
) else (
  call "!CLI_ROOT!\dotnet" msbuild "!SCRIPT_ROOT!\eng\tools\init-build.proj" -bl:"!SCRIPT_ROOT!\artifacts\log\Debug\BuildXPlatTasks_!LogDateStamp!.binlog" -flp:LogFile="!SCRIPT_ROOT!\artifacts\logs\BuildXPlatTasks_!LogDateStamp!.log" -t:PrepareOfflineLocalTools !MSBUILD_ARGUMENTS! %*
  echo kill off the MSBuild server so that on future invocations we pick up our custom SDK Resolver
  call "!CLI_ROOT!\dotnet" build-server shutdown

  call "!CLI_ROOT!\dotnet" msbuild "!SCRIPT_ROOT!\build.proj" "-bl:!SCRIPT_ROOT!\artifacts\log\Debug\Build_!LogDateStamp!.binlog" "-flp:LogFile=!SCRIPT_ROOT!\artifacts\logs\Build_!LogDateStamp!.log" !MSBUILD_ARGUMENTS! %*
)
