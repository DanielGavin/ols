@echo off


if "%1" == "CI" (
    set ODIN="Odin/odin"
) else (
    set ODIN="odin"
)

%ODIN% test tests -collection:shared=src

if %errorlevel% neq 0 goto end_of_build

%ODIN% build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2 
rem %ODIN% build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:0  -debug



:end_of_build
