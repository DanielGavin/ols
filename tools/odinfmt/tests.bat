echo off
cd /D "%~dp0"
odin run tests.odin -file -collection:shared=../../src -out:tests.exe 
if %errorlevel% neq 0 exit 1