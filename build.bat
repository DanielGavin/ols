@echo off


if "%1" == "CI" (
    "Odin/odin.exe" test tests -collection:shared=src -debug -opt:0 
    if %errorlevel% neq 0 exit 1
    "Odin/odin.exe" build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2 -thread-count:1
) else (
    odin.exe build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2
)