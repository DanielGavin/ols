@echo off


if "%1" == "CI" (
    "Odin/odin.exe" test tests -collection:shared=src -debug -opt:0 
    if %errorlevel% neq 0 exit 1
    "Odin/odin.exe" build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2 -thread-count:1
) else if "%1" == "test" (
    odin test tests -collection:shared=src -debug -opt:0 
) else if "%1" == "single_test" (
    odin test tests -collection:shared=src -test-name:%2
) else if "%1" == "debug" (
    odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:0 -debug
) else (
    odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2
)