@echo off

rem odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:0 -debug -llvm-api

if "%1" == "CI" (
    set ODIN="Odin/odin"
) else (
    set ODIN="odin"
)

%ODIN% build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2 -llvm-api
