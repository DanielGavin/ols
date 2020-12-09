@echo off


rem odin run tests\ -show-timings -llvm-api -collection:shared=src -microarch:native -out:test

rem odin build tests\ -show-timings  -collection:shared=src -microarch:native -out:test -debug


rem odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols -debug


rem odin build src\ -llvm-api -show-timings -microarch:native -collection:shared=src -out:ols -debug

odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols -opt:3


