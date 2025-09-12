@echo off

setlocal enabledelayedexpansion


for /f %%a in ('git rev-parse --short HEAD 2^>NUL') do set commit_hash=%%a
for /f %%d in ('powershell -command "[DateTime]::UtcNow.ToString('yyyy-MM-dd')"') do set today=%%d
set version=dev-%today%-%commit_hash%

if "%1" == "test" (
    odin test tests -collection:src=src -debug -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false -extra-linker-flags:"/STACK:4000000,2000000"
) else if "%1" == "single_test" (
    odin test tests -collection:src=src -define:ODIN_TEST_NAMES=%2 -define:ODIN_TEST_TRACK_MEMORY=false -debug -extra-linker-flags:"/STACK:4000000,2000000"
) else if "%1" == "build_test" (
	odin build tests -build-mode:test -collection:src=src -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false -extra-linker-flags:"/STACK:4000000,2000000" %2
) else if "%1" == "debug" (
    odin build src\ -show-timings  -microarch:native  -collection:src=src  -out:ols.exe -o:minimal  -no-bounds-check -use-separate-modules -debug  -extra-linker-flags:"/STACK:4000000,2000000" -define:VERSION=%version%-debug
) else (
    odin build src\ -show-timings -microarch:native -collection:src=src -out:ols.exe -o:speed  -no-bounds-check  -extra-linker-flags:"/STACK:4000000,2000000" -define:VERSION=%version%
)
