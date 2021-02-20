#!/bin/sh -x

#debug mode is the only version that works on linux right now...
odin build src/ -show-timings -microarch:native -collection:shared=src -debug -out:ols

#odin build src/ -show-timings  -collection:shared=src -out:ols -opt:2

