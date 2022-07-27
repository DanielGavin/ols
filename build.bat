@echo on


if "%1" == "CI" (
    set "PATH=%cd%\Odin;%PATH%"
    rem "Odin/odin.exe" test tests -collection:shared=src -debug
    rem if %errorlevel% neq 0 exit 1
    
    odin build src\ -show-timings -collection:shared=src -out:ols.exe -o:speed

    call "tools/odinfmt/tests.bat"
    if %errorlevel% neq 0 exit 1
) else if "%1" == "test" (
    odin test tests -collection:shared=src -debug
) else if "%1" == "single_test" (
    odin test tests -collection:shared=src -test-name:%2
) else if "%1" == "debug" (
    odin build src\ -show-timings  -collection:shared=src  -microarch:native -out:ols.exe -o:minimal  -no-bounds-check -debug
) else (
    odin build src\ -show-timings -microarch:native -collection:shared=src -out:ols.exe -o:speed  -no-bounds-check
)