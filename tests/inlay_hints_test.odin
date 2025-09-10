package tests

import "core:fmt"
import "core:testing"

import test "src:testing"

@(test)
ast_inlay_hints_default_params :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(a := false, b := 42) {}

		main :: proc() {
			my_function([[a = false]][[, b = 42]])
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_default_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_default_params_after_required :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(a: int, b := false, c := 42) {}

		main :: proc() {
			my_function(1[[, b = false]][[, c = 42]])
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_default_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_default_params_after_named :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(a: int, b := false, c := 42) {}

		main :: proc() {
			my_function(a=1[[, b = false]][[, c = 42]])
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_params = true,
			enable_inlay_hints_default_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_default_params_named_ooo :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(a: int, b := false, c := 42) {}

		main :: proc() {
			my_function(1, c=42[[, b = false]])
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_default_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_params :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(param1: int, param2: string) {}

		main :: proc() {
			my_function([[param1 = ]]123, [[param2 = ]]"hello")
		}
		`,
		packages = {},
		config   = {
			enable_inlay_hints_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_mixed_params :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(required: int, optional := false) {}

		main :: proc() {
			my_function([[required = ]]42[[, optional = false]])
		}
		`,
		packages = {},
		config   = {
			enable_inlay_hints_params = true,
			enable_inlay_hints_default_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_selector_call :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Point :: struct {
			x, y: f32,
			move: proc(self: ^Point, dx, dy: f32)
		}

		main :: proc() {
			p: Point
			p->move([[dx = ]]1.0, [[dy = ]]2.0)
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_no_hints_same_name :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(value: int) {}

		main :: proc() {
			value := 42
			my_function(value)
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_params = true,
		},
	}

	// No hints should be shown when argument name matches parameter name
	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_variadic_params :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		variadic_func :: proc(args: ..int) {}

		main :: proc() {
			variadic_func([[args = ]]1, 2, 3)
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_params = true,
		},
	}

	test.expect_inlay_hints(t, &source)
}

@(test)
ast_inlay_hints_disabled :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(param: int, optional := false) {}

		main :: proc() {
			my_function(42)
		}
		`,
		packages = {},
		config = {
			enable_inlay_hints_params = false,
			enable_inlay_hints_default_params = false,
		},
	}

	test.expect_inlay_hints(t, &source)
}
