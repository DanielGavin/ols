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
if [[ $1 == "single_test" ]]
then
    shift

    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin test ../tests -collection:src=../src -test-name:$@ -define:ODIN_TEST_THREADS=1

    shift

    if ([ $? -ne 0 ])
    then
        echo "Test failed"
        exit 1
    fi

	exit 0
fi

if [[ $1 == "test" ]]
then
    shift

    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin test ../tests -collection:src=../src $@ -define:ODIN_TEST_THREADS=1

    if ([ $? -ne 0 ])
    then
        echo "Test failed"
        exit 1
    fi

	exit 0
fi
if [[ $1 == "debug" ]]
then
    shift

    odin build src/ -collection:src=src -out:ols -use-separate-modules -debug $@
    exit 0
fi


odin build src/ -collection:src=src -out:ols -o:speed $@
