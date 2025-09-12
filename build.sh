#!/usr/bin/env bash


VERSION="dev-$(date -u '+%Y-%m-%d')-$(git rev-parse --short HEAD)"

if [[ $1 == "single_test" ]]
then
    shift

    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin test ../tests -collection:src=../src -define:ODIN_TEST_NAMES=$@ -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false

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

    odin test ../tests -collection:src=../src $@ -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false

    if ([ $? -ne 0 ])
    then
        echo "Test failed"
        exit 1
    fi

	exit 0
fi

if [[ $1 == "build_test" ]]
then
    shift

    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin build ../tests -build-mode:test -collection:src=../src $@ -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false

    if ([ $? -ne 0 ])
    then
        echo "Build failed"
        exit 1
    fi

	exit 0
fi

if [[ $1 == "debug" ]]
then
    shift

    odin build src/ -show-timings -collection:src=src -out:ols -microarch:native -no-bounds-check -use-separate-modules -define:VERSION=$VERSION-debug -debug $@
    exit 0
fi

odin build src/ -show-timings -collection:src=src -out:ols -microarch:native -no-bounds-check -o:speed -define:VERSION=$VERSION $@
