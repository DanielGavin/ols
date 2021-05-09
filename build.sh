#!/usr/bin/env bash

if [[ $1 == "CI" ]]
then
    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    ../Odin/odin test ../tests -collection:shared=../src

    if ([ $? -ne 0 ])
    then
        echo "Test failed"
        exit 1
    fi

    cd ..
fi

odin build src/ -show-timings  -collection:shared=src -out:ols -opt:2
