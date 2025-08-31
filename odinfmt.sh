#!/usr/bin/env bash

if [[ $1 == "debug" ]]
then
    shift

	odin build tools/odinfmt/main.odin -file -show-timings -collection:src=src -out:odinfmt -o:none
    exit 0
fi

odin build tools/odinfmt/main.odin -file -show-timings -collection:src=src -out:odinfmt -o:speed
