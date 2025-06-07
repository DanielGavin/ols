package tests

import "core:fmt"
import "core:testing"

import test "src:testing"

@(test)
ast_hover_default_intialized_parameter :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_function :: proc(a := false) {
			b := a{*};
		}

		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.a: bool")
}

@(test)
ast_hover_default_parameter_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		procedure :: proc(called_from: Expr_Called_Type = .None, options := List_Options{}) {
		}

		main :: proc() {
			procedure{*}
		}
		`,
		packages = {},
	}

	test.expect_hover(
		t,
		&source,
		"test.procedure: proc(called_from: Expr_Called_Type = .None, options := List_Options{})",
	)
}
@(test)
ast_hover_parameter :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		main :: proc(cool: int) {
			cool{*}
		}
		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.cool: int")
}

@(test)
ast_hover_external_package_parameter :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"
		main :: proc(cool: my_package.My_Struct) {
			cool{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.cool: My_Struct")
}

@(test)
ast_hover_procedure_package_parameter :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"
		main :: proc(cool: my_packa{*}ge.My_Struct) {
			
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package: package")
}

@(test)
ast_hover_procedure_with_default_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Color :: struct {
			r: int,
			g: int,
			b: int,
			a: int,
		}

		fa{*} :: proc(color_ : Color = { 255, 255, 255, 255 })

		`,
	}

	test.expect_hover(t, &source, "test.fa: proc(color_: Color = {255, 255, 255, 255})")
}

@(test)
ast_hover_same_name_in_selector_and_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Color :: struct {
			color: int,
		}

		f :: proc() {
			color: Color
			color.colo{*}r
		}
		`,
	}

	test.expect_hover(t, &source, "Color.color: int")
}

@(test)
ast_hover_on_sliced_result :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f :: proc() {
			buf: [420]byte
			slic{*}e := buf[2:20]
		}
		`,
	}

	test.expect_hover(t, &source, "test.slice: []byte")
}

@(test)
ast_hover_on_array_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Vec :: [2]f32
		vec: Ve{*}c
		`,
	}

	test.expect_hover(t, &source, "test.Vec: [2]f32")
}

@(test)
ast_hover_on_array_infer_length_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		ve{*}c :: [?]f32{1, 2, 3}
		`,
	}

	test.expect_hover(t, &source, "test.vec: [?]f32")
}

@(test)
ast_hover_on_bitset_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		test :: proc () {
			Foo :: enum {A,B,C}
			derived_{*}bit_set := bit_set[Foo]{}
			}
		`,
	}

	test.expect_hover(t, &source, "test.derived_bit_set: bit_set[Foo]")
}

@(test)
ast_hover_on_union_assertion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		test :: proc () {
			Foo :: union {int}
			foo: Foo = int(0)
			nu{*}m, _ := foo.(int)
		}
		`,
	}

	test.expect_hover(t, &source, "test.num: int")
}

@(test)
ast_hover_on_union_assertion_with_or_continue :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		test :: proc () {
			Foo :: union {int}
			foo: Foo = int(0)
			for {
				nu{*}m := foo.(int) or_continue
			}
		}
		`,
	}

	test.expect_hover(t, &source, "test.num: int")
}

@(test)
ast_hover_on_union_assertion_with_or_else :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		test :: proc () {
			Foo :: union {int}
			foo: Foo = int(0)
			nu{*}m := foo.(int) or_else 0
		}
		`,
	}

	test.expect_hover(t, &source, "test.num: int")
}

@(test)
ast_hover_on_union_assertion_with_or_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		test :: proc () -> bool {
			Foo :: union {int}
			foo: Foo = int(0)
			nu{*}m := foo.(int) or_return
			return true
		}
		`,
	}

	test.expect_hover(t, &source, "test.num: int")
}

@(test)
ast_hover_struct_field_selector_completion :: proc(t: ^testing.T) {

	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
		},
	)

	source := test.Source {
		main     = `package test

		import "my_package"
		My_Foo :: struct {
			bar: my_package.My_Stru{*}ct,
		}

		my_package :: proc() {
		
		}
		
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.My_Struct: struct")
}

@(test)
ast_hover_package_with_value_decl_same_name :: proc(t: ^testing.T) {

	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "my_package", source = `package my_package
		my_package :: proc() -> int {}
		`},
	)

	source := test.Source {
		main     = `package test
		import "my_package"
		main :: proc() {
			_ = my_package.my_pack{*}age()
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.my_package: proc() -> int")
}


@(test)
ast_hover_proc_group :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		add_num :: proc(a, b: int) -> int {return a + b}

		add_vec :: proc(a, b: [2]f32) -> [2]f32 {return a + b}

		add :: proc {
			add_num,
			add_vec,
		}
		main :: proc() {
			foo := ad{*}d(2, 2)
		}	

		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.add: proc(a, b: int) -> int")
}

@(test)
ast_hover_proc_with_proc_parameter :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		a{*}a :: proc(p: proc()) {}
		`,
	}

	test.expect_hover(t, &source, "test.aa: proc(p: proc())")
}

@(test)
ast_hover_proc_with_proc_parameter_with_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		a{*}a :: proc(p: proc() -> int) {}
		`,
	}

	test.expect_hover(t, &source, "test.aa: proc(p: proc() -> int)")
}

@(test)
ast_hover_enum_implicit_selector :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		foo: Foo
		foo = .Fo{*}o1
		`
	}

	test.expect_hover(t, &source, "test.Foo: .Foo1")
}

@(test)
ast_hover_union_implicit_selector :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		Bar :: union { Foo, int }

		bar: Bar
		bar = .Fo{*}o1
		`
	}

	test.expect_hover(t, &source, "test.Bar: .Foo1")
}

@(test)
ast_hover_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			bar: int,
			f: proc(a: int) -> int,
		}

		foo := F{*}oo{}
		`
	}

	test.expect_hover(t, &source, "test.Foo: struct {\n\tbar: int,\n\tf:   proc(a: int) -> int,\n}")
}

@(test)
ast_hover_struct_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			bar: int,
			f: proc(a: int) -> int,
		}

		fo{*}o := Foo{}
		`
	}

	test.expect_hover(t, &source, "test.foo: test.Foo :: struct {\n\tbar: int,\n\tf:   proc(a: int) -> int,\n}")
}

@(test)
ast_hover_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		foo: F{*}oo
		`
	}

	test.expect_hover(t, &source, "test.Foo: enum {\n\tFoo1,\n\tFoo2,\n}")
}

@(test)
ast_hover_enum_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		f{*}oo: Foo
		`
	}

	test.expect_hover(t, &source, "test.foo: test.Foo :: enum {\n\tFoo1,\n\tFoo2,\n}")
}

@(test)
ast_hover_union :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {
			string,
			int,
		}

		foo: F{*}oo
		`
	}

	test.expect_hover(t, &source, "test.Foo: union {\n\tstring,\n\tint,\n}")
}

@(test)
ast_hover_union_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {
			string,
			int,
		}

		f{*}oo: Foo
		`
	}

	test.expect_hover(t, &source, "test.foo: test.Foo :: union {\n\tstring,\n\tint,\n}")
}

@(test)
ast_hover_struct_field_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			b{*}ar: int,
			f: proc(a: int) -> int,
		}

		foo := Foo{
			bar = 1
		}
		`
	}

	test.expect_hover(t, &source, "Foo.bar: int")
}
/*

Waiting for odin fix

@(test)
ast_hover_consecutive_non_mutable :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
a :: int
{*}b :: int
		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.a: boffol")
}
*/

/*
TODO: Allow for testing multiple files
*/
// @(test)
// ast_hover_array_type_multiple_files_hover :: proc(t: ^testing.T) {
// 	source := test.Source {
// 		main     = \
// 		`package test

// 		Vec :: [2]f32
// 		`,
// 		another_file = \
// 		`package test

// 		v: Ve{*}c
// 		`
// 	}

// 	test.expect_hover(t, &source, "test.Vec: [2]f32")
// }
