@echo off

odin run tests\ -llvm-api -show-timings -microarch:native -collection:shared=src -out:ols


odin build src\ -llvm-api -show-timings -microarch:native -collection:shared=src -out:ols


