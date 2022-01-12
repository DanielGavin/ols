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
@(test)
ast_hover_parameter :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc(cool: int) {
			cool*
		}
		`,
		packages = {},
	};

	test.expect_hover(t, &source, "cool: int");
}

@(test)
ast_hover_external_package_parameter :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package);

	append(&packages, test.Package {
		pkg = "my_package",
		source = `package my_package
		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
	});
	source := test.Source {
		main = `package test
		import "my_package"
		main :: proc(cool: my_package.My_Struct) {
			cool*
		}
		`,
		packages = packages[:],
	};

	test.expect_hover(t, &source, "test.cool: My_Struct");
}

@(test)
ast_hover_procedure_package_parameter :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package);

	append(&packages, test.Package {
		pkg = "my_package",
		source = `package my_package
		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
	});
	source := test.Source {
		main = `package test
		import "my_package"
		main :: proc(cool: my_package.My_Stru*ct) {
			
		}
		`,
		packages = packages[:],
	};

	//test.expect_hover(t, &source, "test.cool: My_Struct");
}
