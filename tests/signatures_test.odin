package tests

import "core:testing"
import "core:fmt"

import test "shared:testing"


@(test)
ast_declare_proc_signature :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		main :: proc(*)
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {});
}

@(test)
ast_naked_parens :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		main :: proc() { 

			if node == nil {
				return;
			}

			(*)
			switch n in node.derived {

			}
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {});
}

@(test)
ast_simple_proc_signature :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(a: int) {
		}

		main :: proc() { 
			cool_function(*)
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {"test.cool_function: proc(a: int)"});
}

@(test)
ast_default_assignment_proc_signature :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(a: int, b := context.allocator) {
		}

		main :: proc() { 
			cool_function(*)
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {"test.cool_function: proc(a: int, b := context.allocator)"});
}

@(test)
ast_proc_signature_argument_last_position :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(a: int, b: int) {
		}

		main :: proc() { 
			cool_function(2,*
		}
		`,
		packages = {},
	};

	test.expect_signature_parameter_position(t, &source, 1);
}

@(test)
ast_proc_signature_argument_first_position :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(a: int, b: int) {
		}

		main :: proc() { 
			cool_function(2*,)
		}
		`,
		packages = {},
	};

	test.expect_signature_parameter_position(t, &source, 0);
}


@(test)
ast_proc_signature_argument_move_position :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(a: int, b: int, c: int) {
		}

		main :: proc() { 
			cool_function(2,3*, 3);
		}
		`,
		packages = {},
	};

	test.expect_signature_parameter_position(t, &source, 1);
}

@(test)
ast_proc_signature_argument_complex :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(a: int, b: int, c: int) {
		}

		main :: proc() { 
			cool_function(a(2,5,b(3,sdf[2],{})), *);
		}
		`,
		packages = {},
	};

	test.expect_signature_parameter_position(t, &source, 1);
}

@(test)
ast_proc_signature_argument_open_brace_position :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(a: int, b: int, c: int) {
		}

		main :: proc() { 
			cool_function(2,3, 3*
		}
		`,
		packages = {},
	};

	test.expect_signature_parameter_position(t, &source, 2);
}

@(test)
ast_proc_signature_argument_any_ellipsis_position :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		cool_function :: proc(args: ..any, b := 2) {
		}

		main :: proc() { 
			cool_function(3, 4, 5*)
		}
		`,
		packages = {},
	};

	test.expect_signature_parameter_position(t, &source, 0);
}

@(test)
ast_proc_group_signature_empty_call :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		int_function :: proc(a: int) {
		}

		bool_function :: proc(a: bool) {
		}

		group_function :: proc {
			int_function,
			bool_function,
		};

		main :: proc() {
			group_function(*)
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {"test.int_function: proc(a: int)", "test.bool_function: proc(a: bool)"});
}

@(test)
ast_proc_signature_generic :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		import "core:mem"

		clone_array :: proc(array: $A/[]^$T, allocator: mem.Allocator, unique_strings: ^map[string]string) -> A {
		}
	  
		main :: proc() {
			clone_array(*)
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {"test.clone_array: proc(array: $A/[]^$T, allocator: mem.Allocator, unique_strings: ^map[string]string) -> (A)"});
}

@(test)
ast_proc_group_signature_basic_types :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		int_function :: proc(a: int, b: bool, c: int) {
		}

		bool_function :: proc(a: bool, b: bool, c: bool) {
		}

		group_function :: proc {
			int_function,
			bool_function,
		};

		main :: proc() {
			group_function(2, true, *)
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {"test.int_function: proc(a: int, b: bool, c: int)"});
}


@(test)
ast_proc_group_signature_distinct_basic_types :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		My_Int :: distinct int;

		distinct_function :: proc(a: My_Int, c: int) {
		}

		int_function :: proc(a: int, c: int) {
		}

		group_function :: proc {
			int_function,
			distinct_function,
		};

		main :: proc() {

			a: My_Int;

			group_function(a, *)
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {"test.distinct_function: proc(a: My_Int, c: int)"});
}

@(test)
ast_proc_group_signature_struct :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		My_Int :: distinct int;

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		distinct_function :: proc(a: My_Int, c: int) {
		}

		int_function :: proc(a: int, c: int) {
		}

		struct_function :: proc(a: int, b: My_Struct, c: int) {
		}

		group_function :: proc {
			int_function,
			distinct_function,
			struct_function,
		};

		main :: proc() {
			a: int;
			b: My_Struct;
			group_function(a, b, *)
		}
		`,
		packages = {},
	};

	test.expect_signature_labels(t, &source, {"test.struct_function: proc(a: int, b: My_Struct, c: int)"});
}

@(test)
index_simple_signature :: proc(t: ^testing.T) {

	packages := make([dynamic]test.Package);

	append(&packages, test.Package {
		pkg = "my_package",
		source = `package my_package
		my_function :: proc(a: int, b := context.allocator) {

		}
		`,
	});

    source := test.Source {
		main = `package test

		import "my_package"

		main :: proc() {	
            my_package.my_function(*)
		}
		`,
		packages = packages[:],
	};

    test.expect_signature_labels(t, &source, {"my_package.my_function: proc(a: int, b := context.allocator)"});
}

@(test)
ast_index_builtin_len_proc :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test	
		main :: proc() {
			len(*)
		}
		`,
	packages = {},
	};

	test.expect_signature_labels(t, &source, {"builtin.len: proc(array: Array_Type) -> (int)"});

}