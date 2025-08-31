@echo off

setlocal enabledelayedexpansion

if "%1" == "debug" (
	odin build tools/odinfmt/main.odin -file -show-timings  -collection:src=src -out:odinfmt.exe -o:none
) else (
	odin build tools/odinfmt/main.odin -file -show-timings  -collection:src=src -out:odinfmt.exe -o:speed
)
