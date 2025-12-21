#!/usr/bin/env bash

if [[ -z "$OLS_VERSION" ]]; then
	OLS_VERSION="nightly-$(date -u '+%Y-%m-%d')-$(git rev-parse --short HEAD)"
fi

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

echo "Building ols"
odin build src/ -show-timings -collection:src=src -out:ols -no-bounds-check -o:speed -define:VERSION=$OLS_VERSION $@

echo "Building odinfmt"
odin build tools/odinfmt/main.odin -file -show-timings -collection:src=src -out:odinfmt -no-bounds-check -o:speed $@
