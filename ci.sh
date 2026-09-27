#!/usr/bin/env bash

if [[ -z "$OLS_VERSION" ]]; then
	export OLS_VERSION="nightly-$(date -u '+%Y-%m-%d')-$(git rev-parse --short HEAD)"
fi

export PATH=$PATH:$PWD/Odin

if [[ $1 == "CI" ]]
then
    shift

	echo "Running OLS tests (./build.sh test)"
	./build.sh test "$@"

    if ([ $? -ne 0 ])
    then
        echo "Ols tests failed"
        exit 1
    fi

    tools/odinfmt/tests.sh

    if ([ $? -ne 0 ])
    then
        echo "Odinfmt tests failed"
        exit 1
    fi
fi

echo "Building ols (./build.sh release)"
./build.sh release "$@"

echo "Building odinfmt (./odinfmt.sh)"
./odinfmt.sh "$@"
