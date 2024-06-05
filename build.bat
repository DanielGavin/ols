@echo off

setlocal enabledelayedexpansion
if "%1" == "CI" (
    set "PATH=%cd%\Odin;!PATH!"

    rem odin test tests -collection:src=src -define:ODIN_TEST_THREADS=1
    rem if %errorlevel% neq 0 exit /b 1
    
    odin build src\ -collection:src=src -out:ols.exe -o:speed

    call "tools/odinfmt/tests.bat"
    if %errorlevel% neq 0 exit /b 1
) else if "%1" == "test" (
    odin test tests -collection:src=src -debug -define:ODIN_TEST_THREADS=1
) else if "%1" == "single_test" (
    odin test tests -collection:src=src -define:ODIN_TEST_NAMES=%2 -debug
) else if "%1" == "debug" (
    odin build src\ -show-timings  -collection:src=src  -microarch:native -out:ols.exe -o:minimal  -no-bounds-check -use-separate-modules -debug
) else (
    odin build src\ -show-timings -microarch:native -collection:src=src -out:ols.exe -o:speed  -no-bounds-check
)
