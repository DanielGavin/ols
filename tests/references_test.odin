package tests

import "core:fmt"
import "core:testing"

import test "src:testing"

@(test)
reference_variables_in_function :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		my_function :: proc() {
			a := 2
			b := a
			c := 2 + b
		}
		`,
		packages = {},
	}

	test.expect_symbol_location(
		t,
		&source,
		.Identifier,
		{
			{
				range = {
					start = {line = 2, character = 3},
					end = {line = 2, character = 4},
				},
			},
			{
				range = {
					start = {line = 3, character = 3},
					end = {line = 3, character = 4},
				},
			},
			{
				range = {
					start = {line = 4, character = 3},
					end = {line = 4, character = 4},
				},
			},
		},
	)
}


@(test)
reference_variables_in_function_parameters :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		my_function :: proc(a: int) {
			b := a
			c := 2 + b
		}
		`,
		packages = {},
	}

	test.expect_symbol_location(
		t,
		&source,
		.Identifier,
		{
			{
				range = {
					start = {line = 1, character = 22},
					end = {line = 1, character = 23},
				},
			},
			{
				range = {
					start = {line = 2, character = 3},
					end = {line = 2, character = 4},
				},
			},
			{
				range = {
					start = {line = 3, character = 3},
					end = {line = 3, character = 4},
				},
			},
		},
	)
}

@(test)
reference_selectors_in_function :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		My_Struct :: struct {
			a: int,
		}

		my_function :: proc() {
			my: My_Struct
			my.a = 2
		}
		`,
		packages = {},
	}

	test.expect_symbol_location(
		t,
		&source,
		.Field,
		{
			{
				range = {
					start = {line = 2, character = 3},
					end = {line = 2, character = 4},
				},
			},
		},
	)
}
