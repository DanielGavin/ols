package tests

import "core:testing"
import "core:fmt"

import test "shared:testing"

@(test)
ast_hover_default_intialized_parameter :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		my_function :: proc(a := false) {
			b := a*;
		}

		`,
		source_packages = {},
	};

	test.expect_hover(t, &source, "test.a: bool");
}