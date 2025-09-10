@echo off

setlocal enabledelayedexpansion

for /f %%a in ('git rev-parse --short HEAD 2^>NUL') do set commit_hash=%%a
for /f %%d in ('powershell -command "[DateTime]::UtcNow.ToString('yyyy-MM-dd')"') do set today=%%d
set version=nightly-%today%-%commit_hash%

if "%1" == "CI" (
    set "PATH=%cd%\Odin;!PATH!"

    odin test tests -collection:src=src -define:ODIN_TEST_THREADS=1
    if %errorlevel% neq 0 exit /b 1

    odin build src\ -collection:src=src -out:ols.exe -o:speed  -no-bounds-check -extra-linker-flags:"/STACK:4000000,2000000" -define:VERSION=%version%

    call "tools/odinfmt/tests.bat"
    if %errorlevel% neq 0 exit /b 1
) else (
    odin build src\ -collection:src=src -out:ols.exe -o:speed  -no-bounds-check -extra-linker-flags:"/STACK:4000000,2000000" -define:VERSION=%version%
)
