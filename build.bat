@echo off


if "%1" == "CI" (
    set ODIN="Odin/odin"
) else (
    set ODIN="odin"
)

%ODIN% test tests -llvm-api

if %errorlevel% neq 0 goto end_of_build

%ODIN% build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2 -llvm-api
rem %ODIN% build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:0 -llvm-api -debug



:end_of_build