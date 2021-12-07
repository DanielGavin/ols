package tests 

import "core:testing"
import "core:fmt"

import "shared:common"

import test "shared:testing"

@(test)
ast_goto_untyped_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		xs := 2

		main :: proc() {
			xaa := xs			


			xaa*
		}
		`,
		packages = {},
	};

	location := common.Location {
		range = {
			start = {
				line = 5,
				character = 10,
			},
			end = {
				line = 5,
				character = 12,
			},
		},
		uri = "file:///test/test.odin",
	}

    test.expect_definition_locations(t, &source, {location});
}
