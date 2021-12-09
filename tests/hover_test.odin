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
		packages = {},
	};

	test.expect_hover(t, &source, "test.a: bool");
}

@(test)
ast_hover_default_parameter_enum :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		procedure :: proc(called_from: Expr_Called_Type = .None, options := List_Options{}) {
		}

		main :: proc() {
			procedure*
		}
		`,
		packages = {},
	};

	test.expect_hover(t, &source, "test.procedure: proc(called_from: Expr_Called_Type = .None, options := List_Options{})");
}