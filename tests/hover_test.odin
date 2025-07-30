package tests

import "core:fmt"
import "core:testing"

import test "src:testing"

@(test)
ast_hover_in_nested_blocks :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		
		main :: proc() {
			{
				My_Str{*}uct :: struct {
					property: int,
				}
			}
		}
			
		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.My_Struct: struct {\n\tproperty: int,\n}")
}

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

	test.expect_hover(
		t,
		&source,
		"test.cool: my_package.My_Struct :: struct {\n\tone:   int,\n\ttwo:   int,\n\tthree: int,\n}",
	)
}

@(test)
ast_hover_external_package_parameter_pointer :: proc(t: ^testing.T) {
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
		main :: proc(cool: ^my_package.My_Struct) {
			cool{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(
		t,
		&source,
		"test.cool: ^my_package.My_Struct :: struct {\n\tone:   int,\n\ttwo:   int,\n\tthree: int,\n}",
	)
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

	test.expect_hover(t, &source, "my_package.My_Struct: struct {\n\tone:   int,\n\ttwo:   int,\n\tthree: int,\n}")
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
		`,
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
		`,
	}

	test.expect_hover(t, &source, "test.Foo: .Foo1")
}

@(test)
ast_hover_foreign_package_name_collision :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package

			data :: struct {
				nodes: []node,
			}

			bar :: struct {
			}

			node :: struct {
				bar: ^bar
			}

			get_data :: proc() -> ^data {
				return &data{}
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"
		main :: proc() {
			data := my_package.get_data()

			for node in data.nodes {
				bar := node.b{*}ar
			}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "node.bar: ^my_package.bar")
}
@(test)
ast_hover_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			// this is a doc
			bar: int,
			f: proc(a: int) -> int,
		}

		foo := F{*}oo{}
		`,
	}

	test.expect_hover(
		t,
		&source,
		"test.Foo: struct {\n\t// this is a doc\n\tbar: int,\n\tf:   proc(a: int) -> int,\n}",
	)
}

@(test)
ast_hover_proc_param_with_struct_from_another_package :: proc(t: ^testing.T) {
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
		main :: proc(cool: my_package.My{*}_Struct) {
			cool
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.My_Struct: struct {\n\tone:   int,\n\ttwo:   int,\n\tthree: int,\n}")
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
		`,
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
		`,
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
		`,
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
		`,
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
		`,
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
		`,
	}

	test.expect_hover(t, &source, "Foo.bar: int")
}

@(test)
ast_hover_struct_field_complex_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Bar :: struct {}

		Foo :: struct {
			// Docs
			b{*}ar: ^Bar, // inline docs
			f: proc(a: int) -> int,
		}

		foo := Foo{
			bar = 1
		}
		`,
	}

	test.expect_hover(t, &source, "Foo.bar: ^test.Bar\n Docs\n\n// inline docs")
}

@(test)
ast_hover_within_struct_declaration :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		get_int :: proc() -> int {
			return 42
		}

		Bar :: struct {
			foo: int
		}

		main :: proc() {
			bar := Bar {
				foo = get_i{*}nt(),
			}
		}
		`,
	}

	test.expect_hover(t, &source, "test.get_int: proc() -> int")
}

@(test)
ast_hover_proc_overloading :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo_none :: proc(allocator := context.allocator) -> (int, bool) {
			return 1, false
		}
		foo_int :: proc(i: int, allocator := context.allocator) -> (int, bool) {
			return 2, true
		}
		foo_int2 :: proc(i: int, j: int, allocator := context.allocator) -> (int, bool) {
			return 3, true
		}
		foo_string :: proc(s: string, allocator := context.allocator) -> (int, bool) {
			return 4, false
		}
		foo :: proc {
			foo_none,
			foo_int,
			foo_int2,
			foo_string,
		}

		main :: proc() {
			result, ok := fo{*}o(10, 10)
		}
		`,
	}

	test.expect_hover(
		t,
		&source,
		"test.foo: proc(i: int, j: int, allocator := context.allocator) -> (_: int, _: bool)",
	)
}

@(test)
ast_hover_proc_overloading_no_params :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo_none :: proc(allocator := context.allocator) -> (int, bool) {
			return 1, false
		}
		foo_int :: proc(i: int, allocator := context.allocator) -> (int, bool) {
			return 2, true
		}
		foo_int2 :: proc(i: int, j: int, allocator := context.allocator) -> (int, bool) {
			return 3, true
		}
		foo_string :: proc(s: string, allocator := context.allocator) -> (int, bool) {
			return 4, false
		}
		foo :: proc {
			foo_none,
			foo_int,
			foo_int2,
			foo_string,
		}

		main :: proc() {
			result, ok := fo{*}o()
		}
		`,
	}

	test.expect_hover(t, &source, "test.foo: proc(allocator := context.allocator) -> (_: int, _: bool)")
}

@(test)
ast_hover_proc_overloading_named_arguments :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo_none :: proc() -> (int, bool) {
			return 1, false
		}
		foo_int :: proc(i: int, s := "hello") -> (int, bool) {
			return 2, true
		}
		foo_int2 :: proc(i: int, j: int, s := "hello") -> (int, bool) {
			return 3, true
		}
		foo_string :: proc(s: string, allocator := context.allocator) -> (int, bool) {
			return 4, false
		}
		foo :: proc {
			foo_none,
			foo_int,
			foo_int2,
			foo_string,
		}

		main :: proc() {
			result, ok := fo{*}o(10, "testing")
		}
		`,
	}

	test.expect_hover(t, &source, "test.foo: proc(i: int, s := \"hello\") -> (_: int, _: bool)")
}

@(test)
ast_hover_proc_overloading_in_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		foo_none :: proc(allocator := context.allocator,  loc := #caller_location) -> (int, bool) {
			return 1, false
		}
		foo_int :: proc(i: int, allocator := context.allocator, loc := #caller_location) -> (int, bool) {
			return 2, true
		}
		foo_int2 :: proc(i, j: int, allocator := context.allocator, loc := #caller_location) -> (int, bool) {
			return 3, true
		}
		foo_string :: proc(s: string, allocator := context.allocator, loc := #caller_location) -> (int, bool) {
			return 4, false
		}
		foo :: proc {
			foo_none,
			foo_int,
			foo_int2,
			foo_string,
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			result, ok := my_package.fo{*}o(10)
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(
		t,
		&source,
		"my_package.foo: proc(i: int, allocator := context.allocator, loc := #caller_location) -> (_: int, _: bool)",
	)
}

@(test)
ast_hover_proc_overloading_return_value_from_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		foo_none :: proc(allocator := context.allocator,  loc := #caller_location) -> (int, bool) {
			return 1, false
		}
		foo_int :: proc(i: int, allocator := context.allocator, loc := #caller_location) -> (int, bool) {
			return 2, true
		}
		foo_int2 :: proc(i, j: int, allocator := context.allocator, loc := #caller_location) -> (int, bool) {
			return 3, true
		}
		foo_string :: proc(s: string, allocator := context.allocator, loc := #caller_location) -> (int, bool) {
			return 4, false
		}
		foo :: proc {
			foo_none,
			foo_int,
			foo_int2,
			foo_string,
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			res{*}ult, ok := my_package.foo("Hello, world!")
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.result: int")
}

@(test)
ast_hover_proc_overload_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo_none :: proc(allocator := context.allocator) -> (int, bool) {
			return 1, false
		}
		foo_int :: proc(i: int, allocator := context.allocator) -> (int, bool) {
			return 2, true
		}
		fo{*}o :: proc {
			foo_none,
			foo_int,
		}

		main :: proc() {
			result, ok := foo(10, 10)
		}
		`,
	}

	test.expect_hover(
		t,
		&source,
		"test.foo: proc {\n\tfoo_none :: proc(allocator := context.allocator) -> (_: int, _: bool),\n\tfoo_int :: proc(i: int, allocator := context.allocator) -> (_: int, _: bool),\n}",
	)
}

@(test)
ast_hover_distinguish_names_correctly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Bar :: struct {
			bar: string
		}

		main :: proc() {
			bar := Bar {
				b{*}ar = "Hello, World",
			}
		}
		`,
	}

	test.expect_hover(t, &source, "Bar.bar: string")
}

@(test)
ast_hover_distinguish_names_correctly_variable_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			bar: ^Bar,
		}

		Bar :: struct {
			bar: int,
		}

		main :: proc() {
			foo := &Foo{}
			bar := foo.ba{*}r
		}
		`,
	}

	test.expect_hover(t, &source, "Foo.bar: ^test.Bar")
}

@(test)
ast_hover_sub_string_slices :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			str := "Hello, World!"
			s{*}ub_str := str[0:5]
		}
		`,
	}

	test.expect_hover(t, &source, "test.sub_str: string")
}

@(test)
ast_hover_struct_field_use :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			value: int,
		}

		Bar :: struct {
			foo: Foo,
		}

		main :: proc() {
			bar := Bar{}
			bar.fo{*}o.value += 1
		}
		`,
	}

	test.expect_hover(t, &source, "Bar.foo: test.Foo")
}

@(test)
ast_hover_empty_line_at_top_of_file :: proc(t: ^testing.T) {
	source := test.Source {
		main = `
		package test
		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := F{*}oo{}
		}
		`,
	}

	test.expect_hover(t, &source, "test.Foo: struct {\n\tbar: int,\n}")
}

@(test)
ast_hover_proc_overloading_arg_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			bar: int,
		}

		foo_int :: proc(i: int) {}
		foo_string :: proc(s: string) {}

		foo :: proc {
			foo_int,
			foo_string,
		}

		main :: proc(f: Foo) {
			fo{*}o(f.bar)
		}
		`,
	}

	test.expect_hover(t, &source, "test.foo: proc(i: int)")
}

@(test)
ast_hover_proc_overloading_named_arg_with_selector_expr_with_another_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		foo_none :: proc(x := 1) -> (int, bool) {
			return 1, false
		}
		foo_string :: proc(s: string, x := 1) -> (int, bool) {
			return 2, true
		}
		foo :: proc {
			foo_none,
			foo_string,
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct {
			i: int,
		}

		main :: proc(f: ^Foo) {
			result, ok := my_package.f{*}oo(f.i)
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.foo: proc(x := 1) -> (_: int, _: bool)")
}

@(test)
ast_hover_proc_overloading_named_arg_with_selector_expr_multiple_packages :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		foo_none :: proc(x := 1) -> (int, bool) {
			return 1, false
		}
		foo_string :: proc(s: string, x := 1) -> (int, bool) {
			return 2, true
		}
		foo :: proc {
			foo_none,
			foo_string,
		}
		`,
		},
		test.Package {
			pkg = "my_package2",
			source = `package my_package2
			
			Bar :: struct {
				my_int: int
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"
		import "my_package2"

		Foo :: struct {
			i: int,
		}

		main :: proc(bar: ^my_package2.Bar) {
			result, ok := my_package.f{*}oo(bar.my_int)
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.foo: proc(x := 1) -> (_: int, _: bool)")
}

@(test)
ast_hover_distinguish_symbols_in_packages_proc :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		foo :: proc(x := 1) -> (int, bool) {
			return 1, false
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct {
			i: int,
		}

		main :: proc() {
			foo := Foo{}
			result, ok := my_package.f{*}oo(1)
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.foo: proc(x := 1) -> (_: int, _: bool)")
}

@(test)
ast_hover_distinguish_symbols_in_packages_struct :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "my_package", source = `package my_package

			Foo :: struct {
				foo: string,
			}
		`},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct {
			i: int,
		}

		main :: proc() {
			foo := my_package.F{*}oo{}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.Foo: struct {\n\tfoo: string,\n}")
}

@(test)
ast_hover_distinguish_symbols_in_packages_local_struct :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "my_package", source = `package my_package

			Foo :: struct {
				foo: string,
			}
		`},
	)
	source := test.Source {
		main     = `package test
		import "my_package"


		main :: proc() {
			Foo :: struct {
				i: int,
			}

			foo := my_package.F{*}oo{}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.Foo: struct {\n\tfoo: string,\n}")
}

@(test)
ast_hover_distinguish_symbols_in_packages_variable :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package

			my_var := "my_var"
		`})
	source := test.Source {
		main     = `package test
		import "my_package"


		main :: proc() {
			my_var := 0

			foo := my_package.my_va{*}r
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.my_var: string")
}

@(test)
ast_hover_inside_multi_pointer_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		S1 :: struct {
			s2_ptr: [^]S2,
		}

		S2 :: struct {
			field: S3,
			i: int,
			s: int,
		}

		S3 :: struct {
			s3: int,
		}

		main :: proc() {
			x := S1 {
				s2_ptr = &S2 {
					fi{*}eld = S3 {}
				}
			}
		}
		`,
	}

	test.expect_hover(t, &source, "S2.field: test.S3")
}

@(test)
ast_hover_proc_overloading_parametric_type :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package

			Foo :: struct {}
		`})

	source := test.Source {
		main     = `package test
		import "my_package"

		new_ints :: proc($T: typeid, a, b: int) -> ^T {}
		new_int_string :: proc($T: typeid, a: int, s: string) -> ^T {}

		new :: proc {
			new_ints,
			new_int_string,
		}


		main :: proc() {
			f{*}oo := new(my_package.Foo, 1, 2)
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.foo: ^my_package.Foo :: struct {}")
}

@(test)
ast_hover_proc_overloading_parametric_type_external_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			new_ints :: proc($T: typeid, a, b: int) -> ^T {}
			new_int_string :: proc($T: typeid, a: int, s: string) -> ^T {}

			new :: proc {
				new_ints,
				new_int_string,
			}

			Foo :: struct {}
		`,
		},
	)

	source := test.Source {
		main     = `package test

		import "my_package"		


		main :: proc() {
			f{*}oo := my_package.new(my_package.Foo, 1, 2)
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.foo: ^my_package.Foo :: struct {}")
}

@(test)
ast_hover_struct_documentation :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		F{*}oo :: struct {
			// This is an int
			foo_int: int,
			bar: int, // this is bar
			bazz: int,
		}
		`,
	}

	test.expect_hover(
		t,
		&source,
		"test.Foo: struct {\n\t// This is an int\n\tfoo_int: int,\n\tbar:     int, // this is bar\n\tbazz:    int,\n}",
	)
}

@(test)
ast_hover_struct_documentation_using :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// This is an int
			foo_int: int,
			foo_string: string,
		}

		Bar :: struct {
			// using a foo
			using foo: Foo, // hi

			// this is a string
			bar_string: string,
			bar_int: int, // This is a bar int
		}

		B{*}azz :: struct {
			using bar: Bar,
		}
		`,
	}

	test.expect_hover(
		t,
		&source,
		"test.Bazz: struct {\n\tusing bar:  Bar,\n\n\t// from `using bar: Bar`\n\t// using a foo\n\tusing foo:  Foo, // hi\n\t// this is a string\n\tbar_string: string,\n\tbar_int:    int, // This is a bar int\n\n\t// from `using foo: Foo`\n\t// This is an int\n\tfoo_int:    int,\n\tfoo_string: string,\n}",
	)
}

@(test)
ast_hover_struct_documentation_using_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		InnerInner :: struct {
			field: int,
		}

		Inner :: struct {
			using ii: InnerInner, // InnerInner comment
		}

		Outer :: struct {
			// Inner doc
			using inner: Inner,
		}

		`,
		},
	)
	source := test.Source {
		main     = `package main
		import "my_package"

		F{*}oo :: struct {
			using outer: my_package.Outer,
		}


		main :: proc() {
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(
		t,
		&source,
		"test.Foo: struct {\n\tusing outer: my_package.Outer,\n\n\t// from `using outer: my_package.Outer`\n\t// Inner doc\n\tusing inner: Inner,\n\n\t// from `using inner: Inner`\n\tusing ii:    InnerInner, // InnerInner comment\n\n\t// from `using ii: InnerInner`\n\tfield:       int,\n}",
	)
}

@(test)
ast_hover_proc_comments :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		import "my_package"

		// doc
		foo :: proc() { // do foo

		}

		main :: proc() {
			fo{*}o()
		}
		`,
	}

	test.expect_hover(t, &source, "test.foo: proc()\n doc\n\n// do foo")
}

@(test)
ast_hover_proc_comments_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "my_package", source = `package my_package

			foo :: proc() { // do foo

			}

		`},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			my_package.fo{*}o()
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.foo: proc()\n// do foo")
}

@(test)
ast_hover_struct_field_distinct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		A :: distinct u64
		B :: distinct A

		S :: struct {
			fa: A, // type: fa
			f{*}b: B, // type: fb
			fc: string, // type: string
		}
		`,
	}

	test.expect_hover(t, &source, "S.fb: test.B\n// type: fb")
}

@(test)
ast_hover_struct_field_distinct_external_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package

			A :: distinct u64
		`})
	source := test.Source {
		main     = `package test
		import "my_package"

		S :: struct {
			f{*}b: my_package.A,
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "S.fb: my_package.A")
}

@(test)
ast_hover_distinct_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		A{*} :: distinct u64
		`,
	}

	test.expect_hover(t, &source, "test.A: distinct u64")
}

@(test)
ast_hover_distinct_definition_external_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package

			A :: distinct u64
		`})
	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct {
			a: my_package.A{*},
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.A: distinct u64")
}

@(test)
ast_hover_poly_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		import "small_array"

		Small_Array :: struct($N: int, $T: typeid) where N >= 0 {
			data: [N]T,
			len:  int,
		}

		slice :: proc "contextless" (a: ^$A/Small_Array($N, $T)) -> []T {
			return a.data[:a.len]
		}

		Foo :: struct {
			foo: int,
		}

		MAX :: 4
		foos: Small_Array(MAX, Foo)


		main :: proc()
		{
			foo_slice := slice(&foos)
			for f{*}oo in foo_slice {
			}
		}
		`,
	}

	test.expect_hover(t, &source, "test.foo: test.Foo :: struct {\n\tfoo: int,\n}")
}

@(test)
ast_hover_poly_type_external_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "small_array",
			source = `package small_array

			Small_Array :: struct($N: int, $T: typeid) where N >= 0 {
				data: [N]T,
				len:  int,
			}

			slice :: proc "contextless" (a: ^$A/Small_Array($N, $T)) -> []T {
				return a.data[:a.len]
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "small_array"

		Foo :: struct {
			foo: int,
		}

		MAX :: 4

		foos: small_array.Small_Array(MAX, Foo)

		main :: proc()
		{
			foo_slice := small_array.slice(&foos)
			for f{*}oo in foo_slice {
			}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.foo: test.Foo :: struct {\n\tfoo: int,\n}")
}

@(test)
ast_hover_poly_type_external_package_with_external_type :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "small_array",
			source = `package small_array

			Small_Array :: struct($N: int, $T: typeid) where N >= 0 {
				data: [N]T,
				len:  int,
			}

			slice :: proc "contextless" (a: ^$A/Small_Array($N, $T)) -> []T {
				return a.data[:a.len]
			}
			
			Foo :: struct{}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "small_array"

		Foo :: struct {
			foo: int,
		}

		MAX :: 4

		foos: small_array.Small_Array(MAX, small_array.Foo)

		main :: proc()
		{
			foo_slice := small_array.slice(&foos)
			for f{*}oo in foo_slice {
			}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.foo: small_array.Foo :: struct {}")
}

@(test)
ast_hover_struct_poly_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: struct($T: typeid) {
			foo: T,
		}
		`,
	}

	test.expect_hover(t, &source, "test.Foo: struct($T: typeid) {\n\tfoo: T,\n}")
}

@(test)
ast_hover_poly_proc_mixed_packages :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "foo_package",
			source = `package foo_package
		foo :: proc(t: $T) -> T {
			return t
		}
		`,
		},
		test.Package{pkg = "bar_package", source = `package bar_package
			Bar :: struct {
				bar: int,
			}
		`},
	)

	source := test.Source {
		main     = `package test

		import "foo_package"
		import "bar_package"

		main :: proc() {
			b := bar_package.Bar{}
			f{*} := foo_package.foo(b)
		}
	}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.f: bar_package.Bar :: struct {\n\tbar: int,\n}")
}

@(test)
ast_hover_poly_struct_proc_field :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Foo :: struct($T: typeid) {
			foo: proc(t: ^T) -> T,
		}
		`,
		},
	)

	source := test.Source {
		main     = `package test

		import "my_package"

		Bar :: struct{}

		my_proc :: proc(b: ^Bar) -> Bar {}

		main :: proc() {
			foo: my_package.Foo(Bar) = {
				foo = my_proc,
			}
			foo.f{*}oo()

		}
	}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "Foo.foo: proc(t: ^Bar) -> Bar")
}

@(test)
ast_hover_poly_struct_poly_proc_fields :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		F{*}oo :: struct($S: typeid, $T: typeid) {
			my_proc1: proc(s: S) -> ^S,
			my_proc2: proc(t: ^T) -> T,
			my_proc3: proc(s: ^S, t: T) -> T,
			my_proc4: proc() -> T,
			my_proc5: proc(t: T),
			foo1: T,
			foo2: ^S,
		}
	}
		`,
	}

	test.expect_hover(
		t,
		&source,
		"test.Foo: struct($S: typeid, $T: typeid) {\n\tmy_proc1: proc(s: S) -> ^S,\n\tmy_proc2: proc(t: ^T) -> T,\n\tmy_proc3: proc(s: ^S,t: T) -> T,\n\tmy_proc4: proc() -> T,\n\tmy_proc5: proc(t: T),\n\tfoo1:     T,\n\tfoo2:     ^S,\n}",
	)
}

@(test)
ast_hover_poly_struct_poly_proc_fields_resolved :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bazz :: struct{}
		`})

	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct($S: typeid, $T: typeid) {
			my_proc1: proc(s: S) -> ^S,
			my_proc2: proc(t: T) -> T,
			my_proc3: proc(s: ^S, t: T) -> T,
			foo1: T,
			foo2: ^S,
		}

		Bar :: struct{}

		main :: proc() {
			foo := Fo{*}o(Bar, my_package.Bazz){}
		}
	}
		`,
		packages = packages[:],
	}

	test.expect_hover(
		t,
		&source,
		"test.Foo: struct(Bar, my_package.Bazz) {\n\tmy_proc1: proc(s: Bar) -> ^Bar,\n\tmy_proc2: proc(t: my_package.Bazz) -> my_package.Bazz,\n\tmy_proc3: proc(s: ^my_package.Bazz,t: my_package.Bazz) -> my_package.Bazz,\n\tfoo1:     my_package.Bazz,\n\tfoo2:     ^Bar,\n}",
	)
}

@(test)
ast_hover_bitset_enum_for_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			foos: bit_set[Foo]
			for f{*} in foos {

			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.f: test.Foo :: enum {\n\tA,\n\tB,\n}")
}

@(test)
ast_hover_enum_field_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			a := Foo.A{*}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}


@(test)
ast_hover_enum_field_implicit_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			a: Foo
			a = .A{*}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}

@(test)
ast_hover_enum_field_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A{*},
			B,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}

@(test)
ast_hover_enum_field_definition_with_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A{*} = 1,
			B,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A = 1")
}

@(test)
ast_hover_enum_map_key :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A = 1,
			B,
		}
		main :: proc() {
			m: map[Foo]int
			m[.A{*}] = 2
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A = 1")
}

@(test)
ast_hover_enum_defintion_with_base_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: enum u8 {
			A   = 1,
			Bar = 2,
			C   = 3,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: enum u8 {\n\tA   = 1,\n\tBar = 2,\n\tC   = 3,\n}")
}

@(test)
ast_hover_bit_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: bit_field u8 {
			foo_a: uint | 2,
			foo_aa: uint | 4,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: bit_field u8 {\n\tfoo_a:  uint | 2,\n\tfoo_aa: uint | 4,\n}")
}

@(test)
ast_hover_bit_field_array_backed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: bit_field [4]u8 {
			foo_a: uint | 1,
			foo_aa: uint | 3,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: bit_field [4]u8 {\n\tfoo_a:  uint | 1,\n\tfoo_aa: uint | 3,\n}")
}

@(test)
ast_hover_bit_field_with_docs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: bit_field u8 {
		    // documentation
			foo_a: uintptr | 2,
			foo_bbbb: uint | 4, // comment for b
			// doc
			foo_c: uint | 2, //comment
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo: bit_field u8 {\n\t// documentation\n\tfoo_a:    uintptr | 2,\n\tfoo_bbbb: uint    | 4, // comment for b\n\t// doc\n\tfoo_c:    uint    | 2, //comment\n}",
	)
}

@(test)
ast_hover_struct_with_bit_field_using :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: bit_field u8 {
			foo_a: uint | 2, // foo_a
			// foo_aa
			foo_aa: uint | 4,
		}

		Ba{*}r :: struct {
			using foo: Foo,

			bar: int,
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Bar: struct {\n\tusing foo: Foo,\n\tbar:       int,\n\n\t// from `using foo: Foo (bit_field u8)`\n\tfoo_a:     uint | 2, // foo_a\n\t// foo_aa\n\tfoo_aa:    uint | 4,\n}",
	)
}

@(test)
ast_hover_struct_with_bit_field_using_across_packages :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			Foo :: bit_field u8 {
				foo_a: uint | 1, // foo_a
				// foo_aa
				foo_aa: uint | 7,
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		Bazz :: struct {
			bazz: string, // string for bazz
		}

		Ba{*}r :: struct {
			using foo: my_package.Foo,
			using bazz: Bazz,

			bar: int,
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(
		t,
		&source,
		"test.Bar: struct {\n\tusing foo:  my_package.Foo,\n\tusing bazz: Bazz,\n\tbar:        int,\n\n\t// from `using foo: my_package.Foo (bit_field u8)`\n\tfoo_a:      uint           | 1, // foo_a\n\t// foo_aa\n\tfoo_aa:     uint           | 7,\n\n\t// from `using bazz: Bazz`\n\tbazz:       string, // string for bazz\n}",
	)
}

@(test)
ast_hover_bit_field_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: bit_field u8 {
			foo_a: uint | 2,
			f{*}oo_aa: uint | 6, // last 6 bits
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"Foo.foo_aa: uint | 6\n// last 6 bits",
	)
}

@(test)
ast_hover_bit_field_variable_with_docs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: bit_field u8 {
			// doc
			foo_a: uint | 2, // foo a
			foo_aa: uint | 4,
		}

		main :: proc() {
			foo := Foo{}
			foo.f{*}oo_a = 1
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"Foo.foo_a: uint | 2\n doc\n\n// foo a",
	)
}

@(test)
ast_hover_bit_field_on_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: bit_field u8 {
			// doc
			foo_a: uint | 2, // foo a
			foo_aa: uint | 4,
		}

		Bar :: struct {
			fo{*}o: Foo,
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"Bar.foo: test.Foo",
	)
}

@(test)
ast_hover_bitset_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			Aaa,
			Bbb,
		}

		Foos :: bit_set[Foo]

		main :: proc() {
			foos: Foos
			foos += {.A{*}aa}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .Aaa")
}

@(test)
ast_hover_enumerated_array_key :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			bar: int,
		}


		main :: proc() {
			bar := [Foo]Bar {
				.A{*} = Bar {},
				.B = Bar {},
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}

@(test)
ast_hover_enumerated_array_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			bar: int,
		}


		main :: proc() {
			bar := [Foo]Bar {
				.A = B{*}ar {},
				.B = Bar {},
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Bar: struct {\n\tbar: int,\n}")
}

@(test)
ast_hover_struct_fields_when_not_specifying_type_at_use :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			foo: int,
		}


		Bar :: struct {
			foo: Foo,
		}


		main :: proc() {
			bar: Bar = {
				fo{*}o =
			}
		}
		`,
	}
	test.expect_hover(t, &source, "Bar.foo: test.Foo")
}

@(test)
ast_hover_struct_field_value_when_not_specifying_type_at_use :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B
		}

		Bar :: struct {
			foo: Foo,
		}

		main :: proc() {
			bar: Bar = {
				foo = .B{*}
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .B")
}

@(test)
ast_hover_overload_proc_strings_from_different_packages :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			foo_int :: proc(a: string, b: int){}
			foo_string :: proc(a: string, b: string){}

			foo :: proc{
				foo_int,
				foo_string,
			}

		`,
		},
		test.Package {
			pkg = "str",
			source = `package str
			get_str :: proc() -> string {
				return "foo"
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"
		import "str"

		main :: proc() {
			foo_str := str.get_str()
			my_package.f{*}oo(foo_str, 1)
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(
		t,
		&source,
		"my_package.foo: proc(a: string, b: int)",
	)
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// a docs
			a: int, // a comment
		}

		main :: proc() {
			foo := Foo{}
			foo.a{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.a: int\n a docs\n\n// a comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// a docs
			a{*}: int, // a comment
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.a: int\n a docs\n\n// a comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_struct_types :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: Bar, // bar comment
		}

		Bar :: struct {}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: test.Bar\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_procs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: proc(a: int) -> int, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: proc(a: int) -> int\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_named_procs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		MyProc :: proc(a: int) -> string

		Foo :: struct {
			// bar docs
			bar: MyProc, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: proc(a: int) -> string\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_maps :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: map[int]int, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: map[int]int\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_bit_sets :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: bit_set[0..<10], // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: bit_set[0 ..< 10]\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_unions :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		
		Bar :: union {
			int,
			string,
		}

		Foo :: struct {
			// bar docs
			bar: Bar, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: test.Bar\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_multipointers :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: [^]int, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: [^]int\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_dynamic_arrays :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: [dynamic]int, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: [dynamic]int\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_fixed_arrays :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: [5]int, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: [5]int\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_struct_field_should_show_docs_and_comments_matrix :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			// bar docs
			bar: matrix[4, 5]int, // bar comment
		}

		main :: proc() {
			foo := Foo{}
			foo.bar{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.bar: matrix[4,5]int\n bar docs\n\n// bar comment")
}

@(test)
ast_hover_variable_from_comparison :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foo: Foo,
		}

		main :: proc() {
			bar: Bar
			b{*}azz := bar.bar == .A
		}
		`,
	}
	test.expect_hover(t, &source, "test.bazz: bool")
}

@(test)
ast_hover_named_parameter_same_as_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc(a: int) {}

		main :: proc() {
			a := "hellope"
			foo(a{*} = 0)
		}
		`,
	}
	test.expect_hover(t, &source, "foo.a: int")
}

@(test)
ast_hover_named_parameter_with_default_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc(b := "") {}

		main :: proc() {
			a := "hellope"
			foo(b{*} = a)
		}
		`,
	}
	test.expect_hover(t, &source, "foo.b: string")
}

@(test)
ast_hover_named_parameter_with_default_value_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Bar :: struct{
			bar: int,
		}

		bar := Bar{}

		foo :: proc(a := bar) {}

		main :: proc() {
			b := Bar{}
			foo(a{*} = b)
		}
	`,
	}
	test.expect_hover(t, &source, "foo.a: test.Bar :: struct {\n\tbar: int,\n}")
}

@(test)
ast_hover_inside_where_clause :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(x: [2]int)
			where len(x) > 1,
				  type_of(x{*}) == [2]int {
		}
	`,
	}
	test.expect_hover(t, &source, "test.x: [2]int")
}

@(test)
ast_hover_overloading_with_union :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: int,
		}

		Bar :: struct {
			bar: string,
		}

		FooBar :: union {
			Foo,
			Bar,
		}

		foo_bar :: proc(fb: FooBar) {}
		bar :: proc(bar: Bar) {}

		my_overload :: proc {
			foo_bar,
			bar,
		}

		main :: proc() {
			foo: Foo
			my_overloa{*}d(foo)
		}
	`,
	}
	test.expect_hover(t, &source, "test.my_overload: proc(fb: FooBar)")
}

@(test)
ast_hover_overloading_with_union_and_variant :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: int,
		}

		Bar :: struct {
			bar: string,
		}

		FooBar :: union {
			Foo,
			Bar,
		}

		foo_bar :: proc(fb: FooBar) {}
		bar :: proc(bar: Bar) {}

		my_overload :: proc {
			foo_bar,
			bar,
		}

		main :: proc() {
			bar: Bar
			my_overloa{*}d(bar)
		}
	`,
	}
	test.expect_hover(t, &source, "test.my_overload: proc(bar: Bar)")
}

@(test)
ast_hover_overloading_struct_with_usings :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: int,
		}

		Bar :: struct {
			using f: Foo,

			bar: string,
		}

		Bazz :: struct {
			using b: Bar,

			bazz: i32,
		}


		foo :: proc(f: Foo) {}
		bar :: proc(b: Bar) {}

		foobar :: proc {
			foo,
			bar,
		}

		main :: proc() {
			bazz: Bazz
			fooba{*}r(bazz)
		}
	`,
	}
	test.expect_hover(t, &source, "test.foobar: proc(b: Bar)")
}

@(test)
ast_hover_overloading_struct_with_usings_with_pointers :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: int,
		}

		Bar :: struct {
			using f: Foo,

			bar: string,
		}

		Bazz :: struct {
			using b: Bar,

			bazz: i32,
		}


		foo :: proc(f: ^Foo) {}
		bar :: proc(b: ^Bar) {}

		foobar :: proc {
			foo,
			bar,
		}

		main :: proc() {
			bazz: Bazz
			fooba{*}r(&bazz)
		}
	`,
	}
	test.expect_hover(t, &source, "test.foobar: proc(b: ^Bar)")
}

@(test)
ast_hover_proc_calling_convention :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc "contextless" (a: int) {}
	`,
	}
	test.expect_hover(t, &source, "test.foo: proc \"contextless\" (a: int)")
}

@(test)
ast_hover_proc_directives :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc(a: int) #no_bounds_check {}
	`,
	}
	test.expect_hover(t, &source, "test.foo: proc(a: int) #no_bounds_check")
}

@(test)
ast_hover_proc_attributes :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		@(require_results) f{*}oo :: proc(a: int) -> int {
			return 0
		}
	`,
	}
	test.expect_hover(t, &source, "@(require_results)\ntest.foo: proc(a: int) -> int")
}

@(test)
ast_hover_proc_attributes_key_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		@(disabled=false) f{*}oo :: proc(a: int) -> int {
			return 0
		}
	`,
	}
	test.expect_hover(t, &source, "@(disabled=false)\ntest.foo: proc(a: int) -> int")
}

@(test)
ast_hover_proc_force_inline :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: #force_inline proc(a: int) -> int {
			return 0
		}
	`,
	}
	test.expect_hover(t, &source, "test.foo: #force_inline proc(a: int) -> int")
}

@(test)
ast_hover_proc_force_no_inline :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: #force_no_inline proc(a: int) -> int {
			return 0
		}

		main :: proc() {
			i := f{*}oo(1)
		}
	`,
	}
	test.expect_hover(t, &source, "test.foo: #force_no_inline proc(a: int) -> int")
}

@(test)
ast_hover_builtin_max_with_type_local :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			ma{*}x_u32 :: max(u32)
		}
	`,
	}
	test.expect_hover(t, &source, "test.max_u32: u32")
}

@(test)
ast_hover_builtin_max_with_type_global :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		ma{*}x_u32 :: max(u32)
	`,
	}
	test.expect_hover(t, &source, "test.max_u32: u32")
}

@(test)
ast_hover_builtin_max_ints :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		ma{*}x_int :: max(1, 2, 3, 4)
	`,
	}
	test.expect_hover(t, &source, "test.max_int: int")
}

@(test)
ast_hover_builtin_max_mix :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		
		main :: proc() {
			m{*} := max(1, 2.0, 3, 4.6)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: f64")
}

@(test)
ast_hover_builtin_max_mix_const :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		
		main :: proc() {
			m{*} :: max(1, 2.0, 3, 4.6)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: float")
}

@(test)
ast_hover_builtin_max_mix_global_const :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		m{*} :: max(1, 2.0, 3, 4.6)
	`,
	}
	test.expect_hover(t, &source, "test.m: float")
}

@(test)
ast_hover_builtin_max_value_from_function :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(i: int) -> f64 {
			return 1.0
		}

		main :: proc() {
			m{*} := max(foo(12), 1, 2, 3, 4)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: f64")
}

@(test)
ast_hover_builtin_min :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			m{*} := min(1, 0.5)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: f64")
}

@(test)
ast_hover_builtin_abs:: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			m{*} := abs(-1)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: int")
}

@(test)
ast_hover_builtin_clamp_less:: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			m{*} := clamp(-1, 0.3, 7)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: f64")
}

@(test)
ast_hover_builtin_clamp_greater:: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			m{*} := clamp(8, 0.3, 7)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: int")
}

@(test)
ast_hover_builtin_clamp_between:: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			m{*} := clamp(5, 0.3, 7)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: int")
}

@(test)
ast_hover_builtin_clamp_from_proc:: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> f64 {
			return 1.2
		}

		main :: proc() {
			m{*} := clamp(5, foo(), 7)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: f64")
}

@(test)
ast_hover_enum_explicit_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			foo: Foo = .A{*}
		}
	`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}

@(test)
ast_hover_documentation_reexported :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			// Documentation for Foo
			Foo :: struct{}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		F{*}oo :: my_package.Foo
		`,
		packages = packages[:],
	}
	test.expect_hover(
		t,
		&source,
		"my_package.Foo: struct {}\n Documentation for Foo",
	)
}

@(test)
ast_hover_override_documentation_reexported :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			// Documentation for Foo
			Foo :: struct{}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		// New docs for Foo
		F{*}oo :: my_package.Foo
		`,
		packages = packages[:],
	}
	test.expect_hover(
		t,
		&source,
		"my_package.Foo: struct {}\n New docs for Foo",
	)
}

@(test)
ast_hover_struct_size_and_alignment :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			// this is a doc
			a: u32,
			b: u64,
			c: u16,
		}

		foo := F{*}oo{}
		`,
		packages = {},
		config = {
			enable_hover_struct_size_info = true,
		},
	}

	test.expect_hover(
		t,
		&source,
		"test.Foo: struct {\n\t// this is a doc\n\ta: u32,\n\tb: u64,\n\tc: u16,\n}\nSize: 24 bytes, Alignment: 8 bytes",
	)
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
