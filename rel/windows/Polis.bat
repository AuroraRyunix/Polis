@echo off
rem Starts Polis with a console window: the launcher for when something is
rem wrong and you want to read what the program says. Polis.exe beside this
rem file is the one to double-click otherwise.
rem
rem The data goes where Polis.exe puts it, outside this folder, so that a
rem new version unzipped beside the old one finds it: see "Where your data
rem lives" in the README. POLIS_DATA, when it is set, is left alone.
setlocal
if "%POLIS_DATA%"=="" set POLIS_DATA=%LOCALAPPDATA%\PolisData
if "%PORT%"=="" set PORT=4061
rem What the release writes when it starts goes beside the data, not in here.
if "%RELEASE_TMP%"=="" set RELEASE_TMP=%POLIS_DATA%\tmp
rem Erlang distribution off (see rel/env.bat.eex). `set
rem RELEASE_DISTRIBUTION=sname` before this file gives a node that
rem `bin\polis.bat remote` can attach to, for one session.
if "%RELEASE_DISTRIBUTION%"=="" set RELEASE_DISTRIBUTION=none
echo Starting Polis on http://localhost:%PORT%
echo Data: %POLIS_DATA%
echo Close this window to stop it. Nothing is printed while it is stopped.
echo.
"%~dp0bin\polis.bat" start
endlocal
