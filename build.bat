@echo off

rem odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:0 -debug -llvm-api

odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:2 -llvm-api
