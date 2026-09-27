@echo off

setlocal enabledelayedexpansion


for /f %%a in ('git rev-parse --short HEAD 2^>NUL') do set commit_hash=%%a
for /f %%d in ('powershell -command "[DateTime]::UtcNow.ToString('yyyy-MM-dd')"') do set today=%%d
if not defined OLS_VERSION (
    set version=dev-%today%-%commit_hash%
) else (
    set version=%OLS_VERSION%
)

echo OLS_VERSION=%version%

if "%1" == "test" (
    odin test tests -collection:src=src -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -extra-linker-flags:"/STACK:4000000,2000000" %2 %3 %4 %5 %6 %7 %8 %9
) else if "%1" == "single_test" (
    odin test tests -collection:src=src -define:ODIN_TEST_NAMES=%2 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -extra-linker-flags:"/STACK:4000000,2000000" %3 %4 %5 %6 %7 %8 %9
) else if "%1" == "build_test" (
	odin build tests -build-mode:test -collection:src=src -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -extra-linker-flags:"/STACK:4000000,2000000" %2 %3 %4 %5 %6 %7 %8 %9
) else if "%1" == "release" (
    odin build src\ -show-timings -collection:src=src -out:ols.exe -o:speed -no-bounds-check -extra-linker-flags:"/STACK:4000000,2000000" -define:VERSION=%version% %2 %3 %4 %5 %6 %7 %8 %9
) else if "%1" == "debug" (
    odin build src\ -show-timings  -microarch:native  -collection:src=src  -out:ols.exe -o:minimal  -no-bounds-check -use-separate-modules -debug  -extra-linker-flags:"/STACK:4000000,2000000" -define:VERSION=%version%-debug %2 %3 %4 %5 %6 %7 %8 %9
) else (
    odin build src\ -show-timings -microarch:native -collection:src=src -out:ols.exe -o:speed  -no-bounds-check  -extra-linker-flags:"/STACK:4000000,2000000" -define:VERSION=%version% %1 %2 %3 %4 %5 %6 %7 %8 %9
)
