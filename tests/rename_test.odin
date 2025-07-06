package tests

import "core:fmt"
import "core:testing"

import "src:common"

import test "src:testing"

@(test)
ast_prepare_rename_enum_field_list :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: enum {
			a = 1,
		}

		main :: proc() {
			foo: Foo
			foo = .a{*}
		}
		`,
	}
	range := common.Range{start = {line = 8, character = 10}, end = {line = 8, character = 11}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_enum_field_list_with_constant :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		one :: 1

		Foo :: enum {
			a = on{*}e,
		}
		`,
	}

	range := common.Range{start = {line = 5, character = 7}, end = {line = 5, character = 10}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := Foo{
				b{*}ar = 1,
			}
		}
		`,
	}

	range := common.Range{start = {line = 8, character = 4}, end = {line = 8, character = 7}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_selector :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := Foo{}
			foo.ba{*}r = 1
		}
		`,
	}

	range := common.Range{start = {line = 8, character = 7}, end = {line = 8, character = 10}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := Fo{*}o{}
		}
		`,
	}

	range := common.Range{start = {line = 7, character = 10}, end = {line = 7, character = 13}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_type :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {}

		Foo :: struct {
			bar: B{*}ar,
		}
		`,
	}

	range := common.Range{start = {line = 5, character = 8}, end = {line = 5, character = 11}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_type_package :: proc (t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct {}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct {
			bar: my_package.My_Stru{*}ct,
		}
		`,
		packages = packages[:],
	}

	range := common.Range{start = {line = 4, character = 19}, end = {line = 4, character = 28}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_union_type :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			bar: int,
		}
		
		Bar :: struct {}

		Foo_Bar :: union {
			Fo{*}o,
			Bar,
		}
		`,
	}

	range := common.Range{start = {line = 9, character = 3}, end = {line = 9, character = 6}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_symbol_behind_for :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test
		
		main :: proc() {
			foos := [5]int{1,2,3,4,5}
			for f{*}oo in foos {
			}
		}
		`,
	}

	range := common.Range{start = {line = 4, character = 7}, end = {line = 4, character = 10}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_symbol_behind_for_with_label :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test
		
		main :: proc() {
			foos := [5]int{1,2,3,4,5}
			my_for: for f{*}oo in foos {
			}
		}
		`,
	}

	range := common.Range{start = {line = 4, character = 15}, end = {line = 4, character = 18}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_enumerated_array :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			foos := [Foo]Foo {
				.A{*} = .B,
			}
		}
		`,
	}

	range := common.Range{start = {line = 9, character = 5}, end = {line = 9, character = 6}}
	test.expect_prepare_rename_range(t, &source, range)
}
