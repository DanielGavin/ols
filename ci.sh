#!/usr/bin/env bash


if [[ $1 == "CI" ]]
then
    shift

    export PATH=$PATH:$PWD/Odin
    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin test ../tests -collection:src=../src -o:speed $@ -define:ODIN_TEST_THREADS=1

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

if [[ $1 == "CI_NO_TESTS" ]]
then
    shift

    export PATH=$PATH:$PWD/Odin
fi


odin build src/ -show-timings -collection:src=src -out:ols -no-bounds-check -o:speed $@
