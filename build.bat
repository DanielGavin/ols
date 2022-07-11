@echo off


if "%1" == "CI" (
    rem "Odin/odin.exe" test tests -collection:shared=src -debug
    rem if %errorlevel% neq 0 exit 1
    "Odin/odin.exe" build src\ -show-timings -collection:shared=src -out:ols.exe -o:speed  -thread-count:1
) else if "%1" == "test" (
    odin test tests -collection:shared=src -debug
) else if "%1" == "single_test" (
    odin test tests -collection:shared=src -test-name:%2
) else if "%1" == "debug" (
    odin build src\ -show-timings  -collection:shared=src -out:ols.exe -o:speed  -no-bounds-check -debug
) else (
    odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols.exe -o:speed  -no-bounds-check
)