@echo off


if "%1" == "CI" (
    set ODIN="Odin/odin"
    %ODIN% test tests -collection:shared=src -debug -opt:0 
    if %errorlevel% neq 0 if "%x1" == "CI" exit 1
    %ODIN% build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2 -thread-count:1
    exit 0
) else (
    set ODIN="odin"
)

%ODIN% build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2