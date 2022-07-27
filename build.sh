#!/usr/bin/env bash


if [[ $1 == "CI" ]]
then
    export PATH=$PATH:$PWD/Odin
    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin test ../tests -collection:shared=../src -opt:2

    if ([ $? -ne 0 ])
    then
        echo "Ols tests failed"
        exit 1
    fi

    cd ..

    tools/odinfmt/tests.sh

    if ([ $? -ne 0 ])
    then
        echo "Odinfmt tests failed"
        exit 1
    fi
fi

if [[ $1 == "test" ]]
then
    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin test ../tests -collection:shared=../src

    if ([ $? -ne 0 ])
    then
        echo "Test failed"
        exit 1
    fi

    cd ..
fi

odin build src/ -show-timings  -collection:shared=src -out:ols -o:speed
