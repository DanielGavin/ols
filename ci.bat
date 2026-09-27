@echo off

setlocal enabledelayedexpansion

if not defined OLS_VERSION (
    for /f %%a in ('git rev-parse --short HEAD 2^>NUL') do set commit_hash=%%a
    for /f %%d in ('powershell -command "[DateTime]::UtcNow.ToString('yyyy-MM-dd')"') do set today=%%d
    set "OLS_VERSION=nightly-!today!-!commit_hash!"
)
if "%1" == "CI" (
    shift
    set "PATH=%cd%\Odin;!PATH!"

    call build.bat test
    if errorlevel 1 exit /b 1

    call build.bat release
    if errorlevel 1 exit /b 1

    pushd .
    call "tools/odinfmt/tests.bat"
    if errorlevel 1 (
        popd
        exit /b 1
    )
    popd

    call odinfmt.bat
    if errorlevel 1 exit /b 1
) else (
    call build.bat release %1 %2 %3 %4 %5 %6 %7 %8 %9
    if errorlevel 1 exit /b 1

    call odinfmt.bat %1 %2 %3 %4 %5 %6 %7 %8 %9
    if errorlevel 1 exit /b 1
)
