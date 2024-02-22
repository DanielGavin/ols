#!/usr/bin/env bash

cd "${0%/*}"

odin run tests.odin -file -collection:src=../../src -out:tests.exe 

if ([ $? -ne 0 ]) 
then 
	exit 1 
fi
