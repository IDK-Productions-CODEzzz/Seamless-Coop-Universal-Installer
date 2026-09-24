@echo off
setlocal EnableExtensions DisableDelayedExpansion
:: ============================================================================
::  Install-SeamlessCoop-Mod.bat - Seamless Co-op Installer (All-in-One)
:: ----------------------------------------------------------------------------
::  Installs or updates Yui's Seamless Co-op mod for the Steam versions of:
::    DARK SOULS REMASTERED, DARK SOULS II: Scholar of the First Sin,
::    DARK SOULS III, ELDEN RING, ELDEN RING NIGHTREIGN
::
::  Seamless Co-op is created by Yui:
::    Nexus Mods : https://www.nexusmods.com/profile/Yui
::    GitHub     : https://github.com/yuiamoroll
::  This installer is an unofficial helper, not affiliated with Yui.
::
::  QUICK MAP
::    Main flow ....... "MAIN FLOW" section: one CALL per step, in order
::    Game table ...... :DefineGames - edit there to adjust or add a game
::    Step results .... every step returns 0 = continue, 1 = stop
::    Mod detection ... any .zip whose name contains "Seamless" is a candidate;
::                      the game is identified by the launcher inside it
::                      (<id>_launcher.exe) because Elden Ring's .zip name does
::                      not mention the game. The newest .zip per game wins.
::  Requires Windows 10 1803+ or Windows 11 (built-in tar.exe, PowerShell 5.1)
:: ============================================================================

:: Hardening: this runs elevated from Downloads, so cmd must never start a
:: program just because it sits in the current folder.
set "NoDefaultCurrentDirectoryInExePath=1"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PSRUN="%PS_EXE%" -NoProfile -NonInteractive -Command"
set "TAR_EXE=%SystemRoot%\System32\tar.exe"
set "SCRIPT_DIR=%~dp0"

if not exist "%TAR_EXE%" (
    echo [ERROR] tar.exe was not found. Windows 10 version 1803 or newer is required.
    echo.
    pause
    exit /b 1
)

:: Delayed expansion, enabled below, would corrupt a path containing "!".
set "PATH_CHECK=%SCRIPT_DIR%%TEMP%"
if not "%PATH_CHECK:!=%"=="%PATH_CHECK%" (
    echo [ERROR] This script cannot run from a folder whose path contains "!".
    echo Move this script and the .zip into another folder, then run it again.
    echo.
    pause
    exit /b 1
)

:: Relaunch as administrator (UAC prompt); the game folder needs admin rights.
fltmc >nul 2>&1 || goto :Elevate

:: Elevated instances start in System32, so return to this script's folder.
cd /d "%SCRIPT_DIR%" || (
    echo [ERROR] Could not open this script's folder. If it is on a network or
    echo mapped drive, move the script and the .zip into a local folder instead.
    echo.
    pause
    exit /b 1
)
setlocal EnableDelayedExpansion

:: ============================================================================
::  MAIN FLOW
:: ============================================================================
call :DefineGames
call :ShowBanner
call :FindModZips
if %ZIP_COUNT% EQU 0 (
    call :OfferDownload || goto :End
    call :FindModZips
)
call :SelectModZip    || goto :End
call :FindGameDir     || goto :End
call :ConfirmInstall  || goto :End
call :WaitForGameExit || goto :End
call :ExtractZip      || goto :End
call :InstallFiles    || goto :End
call :CheckPassword
call :CheckShortcut
call :ShowDone

:End
call :CleanupTemp
echo.
pause
exit /b


:: ============================================================================
::  GAME TABLE
:: ============================================================================
:DefineGames
:: One block per game. <id> is Yui's file prefix: <id>_launcher.exe,
:: SeamlessCoop\<id>.dll and SeamlessCoop\<id>_settings.ini
::   Title ..... name shown on screen
::   Folder .... Steam folder: <library>\steamapps\common\<Folder>
::   Exe ....... game exe; the mod goes next to it (<Folder>\Game or <Folder>)
::   Shortcut .. desktop shortcut name; {TM} becomes the trademark symbol
::   Repo ...... official GitHub mirror, owner/repo (empty = Nexus Mods only)
::   Password .. 1 = the mod needs cooppassword set in its settings file
set "GAME_IDS=ds1sc ds2sc ds3sc ersc nrsc"

set "ds1sc.Title=DARK SOULS REMASTERED"
set "ds1sc.Folder=DARK SOULS REMASTERED"
set "ds1sc.Exe=DarkSoulsRemastered.exe"
set "ds1sc.Shortcut=DARK SOULS{TM} REMASTERED Seamless Coop"
set "ds1sc.Repo="
set "ds1sc.Password=1"

set "ds2sc.Title=DARK SOULS II: Scholar of the First Sin"
set "ds2sc.Folder=Dark Souls II Scholar of the First Sin"
set "ds2sc.Exe=DarkSoulsII.exe"
set "ds2sc.Shortcut=DARK SOULS{TM} II Scholar of the First Sin Seamless Coop"
set "ds2sc.Repo=yuiamoroll/DarkSouls2SeamlessCoopRelease"
set "ds2sc.Password=1"

set "ds3sc.Title=DARK SOULS III"
set "ds3sc.Folder=DARK SOULS III"
set "ds3sc.Exe=DarkSoulsIII.exe"
set "ds3sc.Shortcut=DARK SOULS{TM} III Seamless Coop"
set "ds3sc.Repo="
set "ds3sc.Password=1"

set "ersc.Title=ELDEN RING"
set "ersc.Folder=ELDEN RING"
set "ersc.Exe=eldenring.exe"
set "ersc.Shortcut=ELDEN RING Seamless Coop"
set "ersc.Repo=yuiamoroll/EldenRingSeamlessCoopRelease"
set "ersc.Password=1"

set "nrsc.Title=ELDEN RING NIGHTREIGN"
set "nrsc.Folder=ELDEN RING NIGHTREIGN"
set "nrsc.Exe=nightreign.exe"
set "nrsc.Shortcut=ELDEN RING NIGHTREIGN Seamless Coop"
set "nrsc.Repo="
set "nrsc.Password=0"
exit /b 0


:: ============================================================================
::  STEPS
:: ============================================================================
:ShowBanner
title Seamless Co-op Installer
color 0A
echo ==========================================================================
echo    Seamless Co-op Installer - All-in-One
echo ==========================================================================
echo  Seamless Co-op is created by Yui - all credit for the mod goes to them.
echo    Nexus Mods : https://www.nexusmods.com/profile/Yui
echo    GitHub     : https://github.com/yuiamoroll
echo  This installer is an unofficial helper, not affiliated with Yui.
echo.
echo  Supported games:
for %%G in (%GAME_IDS%) do echo    - !%%G.Title!
echo ==========================================================================
echo.
exit /b 0


:FindModZips
:: Checks candidate .zip files newest-first and keeps the newest one per game.
:: Sets ZIP_COUNT and, per entry n: ZIP.n (file name), ZIP.n.Id, ZIP.n.Title
echo Looking for Seamless Co-op .zip files in this folder...
set "ZIP_COUNT=0"
for %%G in (%GAME_IDS%) do set "FOUND.%%G="
for /f "delims=" %%Z in ('dir /b /a-d /o-d "*Seamless*.zip" 2^>nul') do call :ConsiderZip "%%Z"
if %ZIP_COUNT% EQU 0 echo   None found.
exit /b 0


:ConsiderZip
:: Arg 1 = .zip file name. Adds it to the ZIP list unless skipped.
call :InspectZip "%~1"
if errorlevel 2 (
    echo   [SKIP]  "%~1" - Seamless Co-op for a game this script does not support.
    exit /b 0
)
if errorlevel 1 (
    echo   [SKIP]  "%~1" - not a Seamless Co-op mod package.
    exit /b 0
)
if defined FOUND.%Z.Id% (
    echo   [SKIP]  "%~1" - older !%Z.Id%.Title! download; the newest one is used.
    exit /b 0
)
set /a ZIP_COUNT+=1
set "ZIP.%ZIP_COUNT%=%~1"
set "ZIP.%ZIP_COUNT%.Id=%Z.Id%"
set "ZIP.%ZIP_COUNT%.Title=!%Z.Id%.Title!"
set "FOUND.%Z.Id%=1"
echo   [FOUND] !%Z.Id%.Title!  -  "%~1"
exit /b 0


:InspectZip
:: Arg 1 = .zip file name. Reads its file list (no extraction) and identifies
:: the game by the launcher at its root. Sets Z.Id, Z.Launcher, Z.Settings.
:: Returns 0 = supported game, 1 = not a mod package, 2 = unsupported game
set "Z.Id="
set "Z.Launcher="
set "Z.Settings="
for /f "delims=" %%L in ('%TAR_EXE% -tf "%~1" 2^>nul') do (
    set "ENTRY=%%L"
    set "ENTRY=!ENTRY:\=/!"
    if /i "!ENTRY:~-13!"=="_launcher.exe" if "!ENTRY:/=!"=="!ENTRY!" set "Z.Launcher=!ENTRY!"
    if /i "!ENTRY:~0,13!"=="SeamlessCoop/" (
        set "REST=!ENTRY:~13!"
        if /i "!REST:~-13!"=="_settings.ini" if "!REST:/=!"=="!REST!" set "Z.Settings=!REST!"
    )
)
if not defined Z.Launcher exit /b 1
set "Z.Id=!Z.Launcher:~0,-13!"
for %%G in (%GAME_IDS%) do if /i "%%G"=="!Z.Id!" exit /b 0
exit /b 2


:OfferDownload
:: No usable .zip here: offer the titles that have an official GitHub mirror.
echo.
echo No Seamless Co-op .zip file was found next to this script.
echo Nexus Mods requires a free account to download. Yui also publishes these
echo titles on GitHub, which this script can download for you:
set "DL_COUNT=0"
set "KEYS="
for %%G in (%GAME_IDS%) do if defined %%G.Repo (
    set /a DL_COUNT+=1
    set "DL.!DL_COUNT!=%%G"
    set "KEYS=!KEYS!!DL_COUNT!"
    echo   [!DL_COUNT!] !%%G.Title!
)
if %DL_COUNT% EQU 0 echo   None at the moment.
echo   [N] No - exit without downloading
echo.
echo Every other title must be downloaded from Nexus Mods and saved next to
echo this script: https://www.nexusmods.com/profile/Yui
echo.
choice /c %KEYS%N /m "Download one of the titles listed above"
set "PICK=%ERRORLEVEL%"
if %PICK% LSS 1 exit /b 1
if %PICK% GTR %DL_COUNT% (
    echo Nothing was downloaded.
    exit /b 1
)
set "DL_ID=!DL.%PICK%!"
call :DownloadFromGitHub %DL_ID% || exit /b 1
exit /b 0


:DownloadFromGitHub
:: Arg 1 = game id. Saves the latest release .zip of <id>.Repo into this
:: folder, then checks it against the SHA-256 checksum GitHub publishes.
:: PowerShell exit codes: 2 = API unreachable or rate-limited, 3 = no .zip in
:: the release, 4 = download failed, 5 = checksum mismatch (file deleted)
set "SC_REPO=!%~1.Repo!"
set "SC_DEST_DIR=%CD%"
echo.
echo Downloading the latest !%~1.Title! release from GitHub...
%PSRUN% ^
 "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';" ^
 "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12;" ^
 "try { $rel = Invoke-RestMethod -UseBasicParsing -Uri ('https://api.github.com/repos/' + $env:SC_REPO + '/releases/latest') } catch { exit 2 };" ^
 "$asset = @($rel.assets | Where-Object { $_.name -like '*.zip' })[0];" ^
 "if ($null -eq $asset) { exit 3 };" ^
 "$out = Join-Path $env:SC_DEST_DIR $asset.name;" ^
 "Write-Host ('  Release : ' + $rel.name);" ^
 "Write-Host ('  File    : ' + $asset.name + ' (' + [math]::Round($asset.size / 1MB, 1) + ' MB)');" ^
 "try { Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $out } catch { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue; exit 4 };" ^
 "if ($asset.digest -like 'sha256:*') {" ^
 "  if ((Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash -ne $asset.digest.Substring(7)) { Remove-Item -LiteralPath $out -Force; exit 5 };" ^
 "  Write-Host '  SHA-256 matches the checksum published by GitHub.' };" ^
 "exit 0"
set "RC=%ERRORLEVEL%"
if %RC% EQU 0 (
    echo [SUCCESS] Download complete.
    exit /b 0
)
if %RC% EQU 2 echo [ERROR] Could not reach GitHub (offline, or rate-limited - try again later).
if %RC% EQU 3 echo [ERROR] The latest GitHub release does not contain a .zip file.
if %RC% EQU 4 echo [ERROR] The download failed or was interrupted.
if %RC% EQU 5 echo [ERROR] The download did not match GitHub's checksum, so it was deleted.
if %RC% EQU 1 echo [ERROR] PowerShell hit an unexpected error.
echo Download it manually instead: https://github.com/!SC_REPO!/releases/latest
exit /b 1


:SelectModZip
:: One mod found: use it. Several: ask which one (one install per run).
if %ZIP_COUNT% EQU 0 (
    echo.
    echo [ERROR] There is no Seamless Co-op .zip file to install.
    exit /b 1
)
set "SEL=1"
if %ZIP_COUNT% GTR 1 (call :MenuPickZip || exit /b 1)
set "ZIP_FILE=!ZIP.%SEL%!"
set "GAME_ID=!ZIP.%SEL%.Id!"
call :LoadGame %GAME_ID%
call :InspectZip "!ZIP_FILE!"
echo.
echo Selected: !G.Title!
echo   File:   "!ZIP_FILE!"
if not defined Z.Settings (
    echo [ERROR] The .zip has no SeamlessCoop\*_settings.ini file. The mod's
    echo packaging may have changed; check for an updated version of this script.
    exit /b 1
)
exit /b 0


:MenuPickZip
echo.
echo More than one Seamless Co-op mod was found. Which one should be installed?
set "KEYS="
for /l %%i in (1,1,%ZIP_COUNT%) do (
    set "KEYS=!KEYS!%%i"
    echo   [%%i] !ZIP.%%i.Title!
)
echo   [N] None - exit without changes
choice /c %KEYS%N /m "Select a mod"
set "SEL=%ERRORLEVEL%"
if %SEL% LSS 1 exit /b 1
if %SEL% GTR %ZIP_COUNT% (
    echo Nothing was changed.
    exit /b 1
)
exit /b 0


:LoadGame
:: Arg 1 = game id. Copies its table entries into G.* (G.Title, G.Exe, ...).
set "G.Id=%~1"
for %%P in (Title Folder Exe Shortcut Repo Password) do set "G.%%P=!%~1.%%P!"
exit /b 0


:FindGameDir
:: Checks every Steam library for the game, then falls back to asking.
:: GAME_DIR = the folder holding the game's exe, which is where the mod goes.
set "GAME_DIR="
set "STEAM_ROOT="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul ^| findstr /i /c:"InstallPath"') do set "STEAM_ROOT=%%B"
if not defined STEAM_ROOT for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| findstr /i /c:"SteamPath"') do set "STEAM_ROOT=%%B"
if defined STEAM_ROOT (
    set "STEAM_ROOT=!STEAM_ROOT:/=\!"
    call :TryLibrary "!STEAM_ROOT!"
    if exist "!STEAM_ROOT!\steamapps\libraryfolders.vdf" (
        for /f "usebackq tokens=1,*" %%A in ("!STEAM_ROOT!\steamapps\libraryfolders.vdf") do (
            if /i "%%~A"=="path" call :TryLibrary "%%~B"
        )
    )
)
call :TryLibrary "%ProgramFiles(x86)%\Steam"
if not defined GAME_DIR (call :AskGameDir || exit /b 1)
echo.
echo [INFO] Game folder: "!GAME_DIR!"
exit /b 0


:TryLibrary
:: Arg 1 = a Steam library folder (paths read from the .vdf use \\ escapes).
if defined GAME_DIR exit /b 0
set "LIB=%~1"
set "LIB=!LIB:\\=\!"
set "BASE=!LIB!\steamapps\common\!G.Folder!"
if exist "!BASE!\Game\!G.Exe!" (
    set "GAME_DIR=!BASE!\Game"
    exit /b 0
)
if exist "!BASE!\!G.Exe!" set "GAME_DIR=!BASE!"
exit /b 0


:AskGameDir
echo.
echo [WARNING] !G.Title! was not found in your Steam libraries.
echo Tip: in Steam, right-click the game ^> Manage ^> Browse local files, then
echo copy the folder path from the File Explorer address bar.
:AskGameDirPrompt
set "INPUT="
set /p "INPUT=Paste the game folder path here, or press Enter to cancel: "
if defined INPUT set "INPUT=!INPUT:"=!"
if not defined INPUT (
    echo No folder was given. Nothing was changed.
    exit /b 1
)
if "!INPUT:~-1!"=="\" set "INPUT=!INPUT:~0,-1!"
if exist "!INPUT!\Game\!G.Exe!" set "GAME_DIR=!INPUT!\Game"
if exist "!INPUT!\!G.Exe!" set "GAME_DIR=!INPUT!"
if defined GAME_DIR exit /b 0
echo [ERROR] !G.Exe! was not found in that folder. Please try again.
goto :AskGameDirPrompt


:ConfirmInstall
:: Mod files already present = update (the existing settings file is kept).
set "MODE=installed"
if exist "!GAME_DIR!\!Z.Launcher!" set "MODE=updated"
if exist "!GAME_DIR!\SeamlessCoop\" set "MODE=updated"
echo.
if "%MODE%"=="updated" (
    echo Seamless Co-op is already installed for !G.Title!.
    if exist "!GAME_DIR!\SeamlessCoop\!Z.Settings!" echo Updating replaces the mod files but keeps your current !Z.Settings!.
    choice /c YN /m "Would you like to update it"
) else (
    echo Seamless Co-op is not installed for !G.Title! yet.
    choice /c YN /m "Are you sure you want to install it"
)
if errorlevel 2 (
    echo Nothing was changed.
    exit /b 1
)
if errorlevel 1 exit /b 0
exit /b 1


:WaitForGameExit
:: Mod files cannot be replaced while the game is running.
tasklist /fi "imagename eq %G.Exe%" /nh 2>nul | findstr /i /c:"%G.Exe%" >nul
if errorlevel 1 exit /b 0
echo.
echo [WARNING] !G.Title! is running. Close the game completely first.
choice /c RX /m "Press R to retry after closing it, or X to exit"
if errorlevel 2 (
    echo Nothing was changed.
    exit /b 1
)
goto :WaitForGameExit


:ExtractZip
:: Extracts into a unique temp folder, then confirms the key files arrived
:: (antivirus software sometimes quarantines mod files during extraction).
set "TEMP_DIR=%TEMP%\SeamlessCoop_%RANDOM%%RANDOM%"
if exist "%TEMP_DIR%\" goto :ExtractZip
mkdir "%TEMP_DIR%" 2>nul || (
    echo [ERROR] Could not create a temporary folder in "%TEMP%".
    exit /b 1
)
echo.
echo Extracting "!ZIP_FILE!"...
"%TAR_EXE%" -xf "!ZIP_FILE!" -C "%TEMP_DIR%"
if errorlevel 1 (
    echo [ERROR] The .zip could not be extracted. It may be damaged or incomplete,
    echo so try downloading it again.
    exit /b 1
)
call :FindMissingFiles "%TEMP_DIR%"
if defined MISSING (
    echo [ERROR] These files are missing after extraction:!MISSING!
    echo Antivirus software may have quarantined them. Check its protection
    echo history, restore or allow the files, then run this script again.
    exit /b 1
)
exit /b 0


:FindMissingFiles
:: Arg 1 = folder. Sets MISSING to the key mod files it lacks (empty = none).
set "MISSING="
for %%F in ("!Z.Launcher!" "SeamlessCoop\!G.Id!.dll" "SeamlessCoop\!Z.Settings!") do (
    if not exist "%~1\%%~F" set "MISSING=!MISSING! %%~F"
)
exit /b 0


:InstallFiles
:: Keeps an existing settings file (and its password), copies everything else.
if exist "!GAME_DIR!\SeamlessCoop\!Z.Settings!" (
    del /f /q "%TEMP_DIR%\SeamlessCoop\!Z.Settings!" 2>nul
    if exist "%TEMP_DIR%\SeamlessCoop\!Z.Settings!" (
        echo [ERROR] Could not set aside the default settings file. Nothing was changed.
        exit /b 1
    )
    echo [INFO] Keeping your existing SeamlessCoop\!Z.Settings!
)
echo Copying the mod files into the game folder...
xcopy "%TEMP_DIR%\*" "!GAME_DIR!\" /E /H /R /Y >nul
if errorlevel 1 (
    echo [ERROR] Could not copy the mod files into "!GAME_DIR!".
    echo Make sure the game is closed and nothing is using its files, then try again.
    exit /b 1
)
call :FindMissingFiles "!GAME_DIR!"
if defined MISSING (
    echo [ERROR] Missing from the game folder after copying:!MISSING!
    echo Antivirus software may have removed them. Check its protection history.
    exit /b 1
)
echo [SUCCESS] Seamless Co-op for !G.Title! was %MODE%.
exit /b 0


:CheckPassword
:: The mod will not start while cooppassword is empty. Nightreign's settings
:: file has no password line, so it is skipped there.
set "SC_INI=!GAME_DIR!\SeamlessCoop\!Z.Settings!"
call :GetPasswordState
if %PW_STATE% EQU 0 (
    echo [INFO] A co-op password is already set.
    exit /b 0
)
if %PW_STATE% EQU 3 (
    if "!G.Password!"=="1" echo [WARNING] No cooppassword line was found in "!SC_INI!".
    exit /b 0
)
if %PW_STATE% NEQ 2 (
    echo [WARNING] Could not read "!SC_INI!" to check the co-op password.
    exit /b 0
)
echo.
echo [WARNING] No co-op password is set, and the mod will not start without one.
echo Everyone playing together must use the exact same password. Anyone who
echo knows it can join your session, so avoid something easy to guess.
choice /c YN /m "Would you like to set the password now"
if errorlevel 2 (
    echo You can set it later in "!SC_INI!"
    exit /b 0
)
set "SC_PW="
set /p "SC_PW=Type the co-op password and press Enter (blank = skip): "
call :WritePassword
if %PW_WRITE% EQU 3 (
    echo Skipped. You can set it later in "!SC_INI!"
    exit /b 0
)
if %PW_WRITE% NEQ 0 (
    echo [ERROR] The password could not be saved. Set it manually in "!SC_INI!"
    exit /b 0
)
call :GetPasswordState
if %PW_STATE% NEQ 0 echo [ERROR] The password was not saved correctly. Check "!SC_INI!"
exit /b 0


:GetPasswordState
:: Reads SC_INI. PW_STATE: 0 = set, 2 = empty, 3 = no cooppassword line,
:: 4 = file missing, other = unexpected error
%PSRUN% ^
 "$f = $env:SC_INI;" ^
 "if (-not (Test-Path -LiteralPath $f)) { exit 4 };" ^
 "$line = @(Get-Content -LiteralPath $f | Where-Object { $_ -match '^\s*cooppassword\s*=' })[0];" ^
 "if ($null -eq $line) { exit 3 };" ^
 "if ($line -match '^\s*cooppassword\s*=\s*\S') { exit 0 } else { exit 2 }"
set "PW_STATE=%ERRORLEVEL%"
exit /b 0


:WritePassword
:: Replaces only the value on the cooppassword line; the rest of the file is
:: untouched. The password travels in an environment variable (SC_PW) so its
:: characters never pass through batch parsing. PW_WRITE: 0 = saved,
:: 3 = blank input, other = error
%PSRUN% ^
 "$ErrorActionPreference = 'Stop';" ^
 "$pw = ([string]$env:SC_PW).Trim();" ^
 "if ($pw.Length -eq 0) { exit 3 };" ^
 "try {" ^
 "  $text = [IO.File]::ReadAllText($env:SC_INI);" ^
 "  $text = [regex]::Replace($text, '(?im)^([ \t]*cooppassword[ \t]*=)[^\r\n]*', { param($m) $m.Groups[1].Value + ' ' + $pw });" ^
 "  [IO.File]::WriteAllText($env:SC_INI, $text);" ^
 "  Write-Host ('[SUCCESS] Co-op password saved: ' + $pw); exit 0" ^
 "} catch { exit 1 }"
set "PW_WRITE=%ERRORLEVEL%"
exit /b 0


:CheckShortcut
:: Looks for any desktop shortcut (yours or the Public desktop) that already
:: points at this launcher; if there is none, offers to create one.
set "SC_TARGET=!GAME_DIR!\!Z.Launcher!"
set "SC_WORKDIR=!GAME_DIR!"
set "SC_LNK_NAME=!G.Shortcut!"
set "SC_LNK_DESC=Start !G.Title! with Yui's Seamless Co-op mod"
echo.
%PSRUN% ^
 "$target = [IO.Path]::GetFullPath($env:SC_TARGET);" ^
 "$shell = New-Object -ComObject WScript.Shell;" ^
 "$desktops = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) | Where-Object { $_ };" ^
 "foreach ($file in @(Get-ChildItem -LiteralPath $desktops -Filter '*.lnk' -ErrorAction SilentlyContinue)) {" ^
 "  try { $t = $shell.CreateShortcut($file.FullName).TargetPath } catch { $t = '' };" ^
 "  if ($t -eq $target) { Write-Host ('[INFO] A desktop shortcut already exists: ' + $file.Name); exit 0 } };" ^
 "exit 2"
if not errorlevel 1 exit /b 0
choice /c YN /m "Would you like a desktop shortcut that starts the mod"
if errorlevel 2 exit /b 0
%PSRUN% ^
 "$ErrorActionPreference = 'Stop';" ^
 "try {" ^
 "  $name = $env:SC_LNK_NAME.Replace('{TM}', [string][char]0x2122);" ^
 "  $path = Join-Path ([Environment]::GetFolderPath('Desktop')) ($name + '.lnk');" ^
 "  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($path);" ^
 "  $lnk.TargetPath = [IO.Path]::GetFullPath($env:SC_TARGET);" ^
 "  $lnk.WorkingDirectory = $env:SC_WORKDIR;" ^
 "  $lnk.Description = $env:SC_LNK_DESC;" ^
 "  $lnk.Save();" ^
 "  if (-not (Test-Path -LiteralPath $path)) { exit 2 };" ^
 "  Write-Host ('[SUCCESS] Desktop shortcut created: ' + $name); exit 0" ^
 "} catch { exit 1 }"
if errorlevel 1 echo [ERROR] The desktop shortcut could not be created.
exit /b 0


:ShowDone
echo.
echo ==========================================================================
echo    ALL DONE
echo ==========================================================================
echo  Play !G.Title! with Seamless Co-op by starting the mod's launcher
echo  (or the desktop shortcut, if you made one):
echo    "!GAME_DIR!\!Z.Launcher!"
echo  Pressing Play in Steam starts the normal game without the mod.
echo  Steam must be running and online. Everyone in your group needs the same
if "!G.Password!"=="1" (echo  mod version and the same co-op password.) else (echo  mod version.)
echo ==========================================================================
exit /b 0


:CleanupTemp
if defined TEMP_DIR if exist "%TEMP_DIR%\" rd /s /q "%TEMP_DIR%" 2>nul
exit /b 0


:: ============================================================================
::  ELEVATION (reached by GOTO from the top, before delayed expansion)
:: ============================================================================
:Elevate
:: The "elevated" argument marks the relaunched copy so a failed elevation can
:: never loop. cmd /c gets the path wrapped in an extra pair of quotes so
:: folders with spaces, "&" or parentheses survive the handoff.
if /i "%~1"=="elevated" (
    echo [ERROR] Administrator rights are required but could not be obtained.
    echo.
    pause
    exit /b 1
)
echo Requesting administrator rights...
set "SC_SELF=%~f0"
%PSRUN% ^
 "$q = [char]34;" ^
 "try { Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ' + $q + $q + $env:SC_SELF + $q + ' elevated' + $q) -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if errorlevel 1 (
    echo [ERROR] The administrator prompt was declined, so nothing was changed.
    echo.
    pause
)
exit /b
