#!/usr/bin/env bash

if [[ $1 == "CI" ]]
then 
    ODIN="Odin/odin"
else
    ODIN="odin"
fi

#BUG in odin test, it makes the executable with the same name as a folder and gets confused.
#${ODIN} test tests -llvm-api

#if [ $? -ne 0 ]
#then
#    echo "Test failed"
#    exit 1
#fi

${ODIN} build src/ -show-timings  -collection:shared=src -out:ols -opt:2 -microarch=native
