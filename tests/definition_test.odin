package tests

import "core:testing"
import "core:fmt"

import "shared:common"

import test "shared:testing"

@(test)
ast_goto_comp_lit_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }
        
        main :: proc() {
            point := Point {
                x{*} = 2, y = 5, z = 0,
            }
        } 
		`,
	}

	location := common.Location {
		range = {
			start = {line = 2, character = 12},
			end = {line = 2, character = 13},
		},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_comp_lit_field_indexed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }
        
        main :: proc() {
            point := [2]Point {
                {x{*} = 2, y = 5, z = 0},
                {y = 10, y = 20, z = 10},
            }
        } 
		`,
	}

	location := common.Location {
		range = {
			start = {line = 2, character = 12},
			end = {line = 2, character = 13},
		},
	}

	test.expect_definition_locations(t, &source, {location})
}
