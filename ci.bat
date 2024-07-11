@echo off

setlocal enabledelayedexpansion
if "%1" == "CI" (
    set "PATH=%cd%\Odin;!PATH!"

    rem odin test tests -collection:src=src -define:ODIN_TEST_THREADS=1
    rem if %errorlevel% neq 0 exit /b 1
    
    odin build src\ -collection:src=src -out:ols.exe -o:speed

    call "tools/odinfmt/tests.bat"
    if %errorlevel% neq 0 exit /b 1
) else (
     odin build src\ -collection:src=src -out:ols.exe -o:speed  -no-bounds-check
)