@echo off
setlocal EnableExtensions DisableDelayedExpansion
:: ============================================================================
::  Seamless-Coop-Universal-Installer.bat - Seamless Co-op Universal Installer
:: ----------------------------------------------------------------------------
::  Installs or updates Yui's Seamless Co-op mod for the Steam versions of:
::    DARK SOULS REMASTERED, DARK SOULS II: Scholar of the First Sin,
::    DARK SOULS III, ELDEN RING, ELDEN RING NIGHTREIGN
::
::  Seamless Co-op is created by Yui:
::    Nexus Mods : https://www.nexusmods.com/profile/Yui
::    GitHub     : https://github.com/yuiamoroll
::  This installer is an unofficial helper, not affiliated with Yui.
::  It was written with the help of AI (Anthropic's Claude).
::
::  QUICK MAP
::    Main flow ....... "MAIN FLOW" section: one CALL per step, in order
::    Game table ...... :DefineGames - edit there to adjust or add a game
::    Step results .... every step returns 0 = continue, 1 = stop
::    Debug output .... run with /debug, or set DEBUG=1 near the top
::    Mod detection ... any .zip whose name contains "Seamless" is a candidate;
::                      the game is identified by the launcher inside it
::                      (<id>_launcher.exe) because Elden Ring's .zip name does
::                      not mention the game. The newest .zip per game wins.
::    Downloads ....... a game with a GitHub mirror (Repo in the table) is
::                      always offered as a download when no .zip for it is
::                      here, whether or not the game is installed.
::    Game folder ..... found in the Steam libraries by the game's exe (Exe in
::                      the table); if it is not found, the user is asked to
::                      paste the folder, before anything is downloaded.
::  Requires Windows 10 1803+ or Windows 11 (built-in tar.exe, PowerShell 5.1)
:: ============================================================================

:: Hardening: this runs elevated from Downloads, so cmd must never start a
:: program just because it sits in the current folder.
set "NoDefaultCurrentDirectoryInExePath=1"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PSRUN="%PS_EXE%" -NoProfile -NonInteractive -Command"
set "TAR_EXE=%SystemRoot%\System32\tar.exe"
set "SCRIPT_DIR=%~dp0"

:: Debug output (extra detail for troubleshooting): set to 1 here, or run the
:: script from a Command Prompt with /debug. It is passed on when elevating.
set "DEBUG=0"
if /i "%~1"=="/debug" set "DEBUG=1"
if /i "%~2"=="/debug" set "DEBUG=1"

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
call :BuildChoices
call :SelectGame      || goto :End
call :LoadSteamLibraries
call :FindGameDir     || goto :End
if "%DO_DOWNLOAD%"=="1" (
    call :DownloadFromGitHub %GAME_ID% || goto :End
    call :FindModZips
)
call :LoadSelectedMod || goto :End
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
title Seamless Co-op Universal Installer
color 0A
echo ==========================================================================
echo    Seamless Co-op Universal Installer
echo ==========================================================================
echo  Seamless Co-op is created by Yui - all credit for the mod goes to them.
echo    Nexus Mods : https://www.nexusmods.com/profile/Yui
echo    GitHub     : https://github.com/yuiamoroll
echo  This installer is an unofficial helper, not affiliated with Yui.
echo  It was written with the help of AI (Anthropic's Claude).
echo.
echo  Supported games:
for %%G in (%GAME_IDS%) do echo    - !%%G.Title!
if "%DEBUG%"=="1" echo  [DEBUG] Debug output is on.
echo ==========================================================================
exit /b 0


:FindModZips
:: Checks candidate .zip files newest-first and keeps the newest one per game.
:: Sets FOUND.<id> = file name for each game with a usable .zip here.
if "%DEBUG%"=="1" (
    echo.
    echo Looking for Seamless Co-op .zip files in this folder...
)
set "ZIP_COUNT=0"
for %%G in (%GAME_IDS%) do set "FOUND.%%G="
for /f "delims=" %%Z in ('dir /b /a-d /o-d "*Seamless*.zip" 2^>nul') do call :ConsiderZip "%%Z"
if "%DEBUG%"=="1" if %ZIP_COUNT% EQU 0 echo   None found.
exit /b 0


:ConsiderZip
:: Arg 1 = .zip file name. Records it as FOUND.<id> unless it is skipped.
call :InspectZip "%~1"
if errorlevel 2 (
    if "%DEBUG%"=="1" echo   [SKIP]  "%~1" - Seamless Co-op for a game this script does not support.
    exit /b 0
)
if errorlevel 1 (
    if "%DEBUG%"=="1" echo   [SKIP]  "%~1" - not a Seamless Co-op mod package.
    exit /b 0
)
if defined FOUND.%Z.Id% (
    if "%DEBUG%"=="1" echo   [SKIP]  "%~1" - older !%Z.Id%.Title! download; the newest one is used.
    exit /b 0
)
set "FOUND.%Z.Id%=%~1"
set /a ZIP_COUNT+=1
if "%DEBUG%"=="1" echo   [FOUND] !%Z.Id%.Title!  -  "%~1"
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


:LoadSteamLibraries
:: Builds STEAM_LIBS, a list of quoted Steam library folders: Steam's own
:: folder, every library in its libraryfolders.vdf, and the default folder.
set "STEAM_LIBS="
set "STEAM_ROOT="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul ^| findstr /i /c:"InstallPath"') do set "STEAM_ROOT=%%B"
if not defined STEAM_ROOT for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| findstr /i /c:"SteamPath"') do set "STEAM_ROOT=%%B"
if defined STEAM_ROOT (
    set "STEAM_ROOT=!STEAM_ROOT:/=\!"
    call :AddLibrary "!STEAM_ROOT!"
    if exist "!STEAM_ROOT!\steamapps\libraryfolders.vdf" (
        for /f "usebackq tokens=1,*" %%A in ("!STEAM_ROOT!\steamapps\libraryfolders.vdf") do (
            if /i "%%~A"=="path" call :AddLibrary "%%~B"
        )
    )
)
call :AddLibrary "%ProgramFiles(x86)%\Steam"
if "%DEBUG%"=="1" echo.
if "%DEBUG%"=="1" for %%L in (!STEAM_LIBS!) do echo   [STEAM] Library: %%~L
if "%DEBUG%"=="1" if not defined STEAM_LIBS echo   [STEAM] No Steam library folders were found.
exit /b 0


:AddLibrary
:: Arg 1 = a Steam library folder (paths read from the .vdf use \\ escapes).
:: Adds it to STEAM_LIBS if it exists and is not listed yet.
set "LIB=%~1"
set "LIB=!LIB:\\=\!"
if "!LIB:~-1!"=="\" set "LIB=!LIB:~0,-1!"
if not exist "!LIB!\steamapps\" exit /b 0
for %%L in (!STEAM_LIBS!) do if /i "%%~L"=="!LIB!" exit /b 0
set "STEAM_LIBS=!STEAM_LIBS! "!LIB!""
exit /b 0


:LocateGame
:: Arg 1 = game id. Searches the Steam libraries without asking anything.
:: Sets GAME_DIR to the folder holding the game's exe, or leaves it empty.
set "GAME_DIR="
for %%L in (!STEAM_LIBS!) do if not defined GAME_DIR call :TryLibrary %%L %~1
exit /b 0


:TryLibrary
:: Arg 1 = Steam library folder, Arg 2 = game id. Sets GAME_DIR when the
:: game's exe is in <library>\steamapps\common\<Folder>\Game or <Folder>.
set "BASE=%~1\steamapps\common\!%~2.Folder!"
if exist "!BASE!\Game\!%~2.Exe!" (
    set "GAME_DIR=!BASE!\Game"
    exit /b 0
)
if exist "!BASE!\!%~2.Exe!" set "GAME_DIR=!BASE!"
exit /b 0


:BuildChoices
:: Menu entries in game table order: each game with a .zip found here, plus
:: each game with a GitHub mirror that has no .zip here (a download entry;
:: whether the game is installed is checked only after it is picked).
:: Sets CHOICE_COUNT, DL_OFFERED (1 = a download is listed) and, per entry n:
:: CH.n (game id), CH.n.Label, CH.n.Download (1 = download from GitHub first)
set "CHOICE_COUNT=0"
set "DL_OFFERED=0"
for %%G in (%GAME_IDS%) do call :AddChoice %%G
exit /b 0


:AddChoice
:: Arg 1 = game id. Adds it to the menu if it qualifies (see BuildChoices).
set "DL_FLAG=0"
if not defined FOUND.%~1 (
    if not defined %~1.Repo exit /b 0
    if "%DEBUG%"=="1" echo   [GITHUB] !%~1.Title! - no .zip here, so a download is offered.
    set "DL_FLAG=1"
    set "DL_OFFERED=1"
)
set /a CHOICE_COUNT+=1
set "CH.%CHOICE_COUNT%=%~1"
set "CH.%CHOICE_COUNT%.Download=%DL_FLAG%"
set "CH.%CHOICE_COUNT%.Label=!%~1.Title!"
if "%DL_FLAG%"=="1" set "CH.%CHOICE_COUNT%.Label=!%~1.Title! (download from GitHub)"
exit /b 0


:SelectGame
:: No entries: nothing to install. One entry whose .zip is here: use it
:: without asking. Otherwise (several entries, or a download): show the menu.
:: Games with a GitHub mirror are always listed, so with the current table
:: the menu always shows. Sets GAME_ID, DO_DOWNLOAD (1 = download it from
:: GitHub first) and the chosen game's G.* entries (see LoadGame).
if %CHOICE_COUNT% EQU 0 (
    echo.
    echo No usable Seamless Co-op .zip file was found next to this script.
    echo Download the mod for your game from Nexus Mods, save the .zip next to
    echo this script, then run it again: https://www.nexusmods.com/profile/Yui
    exit /b 1
)
set "SEL=1"
set "SHOW_MENU=0"
if %CHOICE_COUNT% GTR 1 set "SHOW_MENU=1"
if "!CH.1.Download!"=="1" set "SHOW_MENU=1"
if "%SHOW_MENU%"=="1" (call :MenuPickGame || exit /b 1)
set "GAME_ID=!CH.%SEL%!"
set "DO_DOWNLOAD=!CH.%SEL%.Download!"
call :LoadGame %GAME_ID%
exit /b 0


:MenuPickGame
echo.
echo Which game would you like to install Seamless Co-op for?
for /l %%i in (1,1,%CHOICE_COUNT%) do echo   [%%i] !CH.%%i.Label!
echo   [N] None - exit without changes
if "%DL_OFFERED%"=="1" (
    echo.
    echo Not listed? Download that game's mod from Nexus Mods and save the .zip
    echo next to this script: https://www.nexusmods.com/profile/Yui
    echo.
)
call :AskNumber %CHOICE_COUNT%
if %PICK% EQU 0 (
    echo Nothing was changed.
    exit /b 1
)
set "SEL=%PICK%"
exit /b 0


:AskNumber
:: Arg 1 = highest option number. Waits for a number plus Enter, so a stray
:: key press is never taken as the answer. PICK = 1 to Arg 1, or 0 for N.
set "RANGE=1-%~1"
if "%~1"=="1" set "RANGE=1"
set "PICK="
set /p "PICK=Type %RANGE% or N, then press Enter: "
if /i "!PICK!"=="N" (
    set "PICK=0"
    exit /b 0
)
for /l %%i in (1,1,%~1) do if "!PICK!"=="%%i" exit /b 0
echo Please type one of the options listed above.
goto :AskNumber


:DownloadFromGitHub
:: Arg 1 = game id. Saves the latest release .zip of <id>.Repo into this
:: folder, then checks it against the SHA-256 checksum GitHub publishes.
:: A file name without "Seamless" gets a "Seamless Co-op - " prefix so that
:: FindModZips always finds the download.
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
 "$name = $asset.name; if ($name -notlike '*Seamless*') { $name = 'Seamless Co-op - ' + $name };" ^
 "$out = Join-Path $env:SC_DEST_DIR $name;" ^
 "Write-Host ('  Release : ' + $rel.name);" ^
 "Write-Host ('  File    : ' + $name + ' (' + [math]::Round($asset.size / 1MB, 1) + ' MB)');" ^
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


:LoadSelectedMod
:: Picks the chosen game's .zip, local or just downloaded, and inspects it.
set "ZIP_FILE=!FOUND.%GAME_ID%!"
if not defined ZIP_FILE (
    echo [ERROR] The downloaded file was not recognized as Seamless Co-op for
    echo !G.Title!. Check the .zip in this folder.
    exit /b 1
)
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


:LoadGame
:: Arg 1 = game id. Copies its table entries into G.* (G.Title, G.Exe, ...).
set "G.Id=%~1"
for %%P in (Title Folder Exe Shortcut Repo Password) do set "G.%%P=!%~1.%%P!"
exit /b 0


:FindGameDir
:: Finds the chosen game in the Steam libraries, or asks for its folder.
:: GAME_DIR = the folder holding the game's exe, which is where the mod goes.
call :LocateGame %G.Id%
if not defined GAME_DIR (call :AskGameDir || exit /b 1)
if "%DEBUG%"=="1" (
    echo.
    echo [INFO] Game folder: "!GAME_DIR!"
)
exit /b 0


:AskGameDir
:: Asks until the game's exe is found in the pasted folder or in its Game
:: subfolder. A pasted file path, such as the exe itself, means its folder.
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
for %%I in ("!INPUT!") do if exist "%%~fI" if not exist "%%~fI\" set "INPUT=%%~dpI"
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
call :FindMissingFiles TEMP_DIR
if defined MISSING (
    echo [ERROR] These files are missing after extraction:!MISSING!
    echo Antivirus software may have quarantined them. Check its protection
    echo history, restore or allow the files, then run this script again.
    exit /b 1
)
exit /b 0


:FindMissingFiles
:: Arg 1 = NAME of the variable holding the folder; reading it by name keeps
:: any character in the path intact. Sets MISSING to the key mod files the
:: folder lacks (empty = none).
set "MISSING="
for %%F in ("!Z.Launcher!" "SeamlessCoop\!G.Id!.dll" "SeamlessCoop\!Z.Settings!") do (
    if not exist "!%~1!\%%~F" set "MISSING=!MISSING! %%~F"
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
    if "%DEBUG%"=="1" echo [INFO] Keeping your existing SeamlessCoop\!Z.Settings!
)
if "%DEBUG%"=="1" echo Copying the mod files into the game folder...
xcopy "%TEMP_DIR%\*" "!GAME_DIR!\" /E /H /R /Y >nul
if errorlevel 1 (
    echo [ERROR] Could not copy the mod files into "!GAME_DIR!".
    echo Make sure the game is closed and nothing is using its files, then try again.
    exit /b 1
)
call :FindMissingFiles GAME_DIR
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
:: never loop (/debug is passed along too). cmd /c gets the path wrapped in an
:: extra pair of quotes so folders with spaces, "&" or parentheses survive.
if /i "%~1"=="elevated" (
    echo [ERROR] Administrator rights are required but could not be obtained.
    echo.
    pause
    exit /b 1
)
echo Requesting administrator rights...
set "SC_SELF=%~f0"
set "SC_ARGS=elevated"
if "%DEBUG%"=="1" set "SC_ARGS=elevated /debug"
%PSRUN% ^
 "$q = [char]34;" ^
 "try { Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ' + $q + $q + $env:SC_SELF + $q + ' ' + $env:SC_ARGS + $q) -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if errorlevel 1 (
    echo [ERROR] The administrator prompt was declined, so nothing was changed.
    echo.
    pause
)
exit /b
