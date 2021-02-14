#!/bin/sh -x

odin build src/ -show-timings -microarch:native -collection:shared=src -out:ols -opt:1
