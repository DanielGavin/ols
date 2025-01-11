#!/usr/bin/env bash


if [[ $1 == "single_test" ]]
then
    shift

    #BUG in odin test, it makes the executable with the same name as a folder and gets confused.
    cd tests

    odin test ../tests -collection:src=../src -test-name:$@ -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false

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
if [[ $1 == "debug" ]]
then
    shift

    odin build src/ -show-timings -collection:src=src -out:ols -microarch:native -no-bounds-check -use-separate-modules -debug $@
    exit 0
fi

version="$(git describe --tags --abbrev=7)"
version="${version%-*}:${version##*-}"
sed "s|VERSION :: .*|VERSION :: \"${version}\"|g" src/main.odin > /tmp/main.odin.build && mv -f /tmp/main.odin.build src/main.odin

odin build src/ -show-timings -collection:src=src -out:ols -microarch:native -no-bounds-check -o:speed $@
