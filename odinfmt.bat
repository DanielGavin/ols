@echo off

setlocal enabledelayedexpansion

if "%1" == "debug" (
	shift
	odin build tools/odinfmt/main.odin -file -show-timings  -collection:src=src -out:odinfmt.exe -o:none -debug %1 %2 %3 %4 %5 %6 %7 %8 %9
) else (
	odin build tools/odinfmt/main.odin -file -show-timings  -collection:src=src -out:odinfmt.exe -o:speed %1 %2 %3 %4 %5 %6 %7 %8 %9
)
