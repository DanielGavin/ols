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

	test.expect_hover(t, &source, "test.Bar: .Foo1")
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

	test.expect_hover(t, &source, "node.bar: ^my_package.bar :: struct {}")
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

	test.expect_hover(t, &source, "test.Foo: struct {\n\t// this is a doc\n\tbar: int,\n\tf:   proc(a: int) -> int,\n}")
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

	test.expect_hover(t, &source, "Foo.bar: ^test.Bar // inline docs")
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

	test.expect_hover(t, &source, "Foo.bar: ^test.Bar :: struct {\n\tbar: int,\n}")
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

	test.expect_hover(t, &source, "Bar.foo: test.Foo :: struct {\n\tvalue: int,\n}")
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

	test.expect_hover(t, &source, "S2.field: S3")
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

	test.expect_hover(t, &source, "test.Foo: struct {\n\t// This is an int\n\tfoo_int: int,\n\tbar:     int, // this is bar\n\tbazz:    int,\n}")
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

	test.expect_hover(t, &source, "test.Bazz: struct {\n\tusing bar:  Bar,\n\n\t// from `using bar: Bar`\n\t// using a foo\n\tusing foo:  Foo, // hi\n\t// this is a string\n\tbar_string: string,\n\tbar_int:    int, // This is a bar int\n\n\t// from `using foo: Foo`\n\t// This is an int\n\tfoo_int:    int,\n\tfoo_string: string,\n}")
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
		main = `package main
		import "my_package"

		F{*}oo :: struct {
			using outer: my_package.Outer,
		}


		main :: proc() {
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.Foo: struct {\n\tusing outer:     my_package.Outer,\n\n\t// from `using outer: my_package.Outer`\n\t// Inner doc\n\tusing inner:     Inner,\n\n\t// from `using inner: Inner`\n\tusing ii:  InnerInner, // InnerInner comment\n\n\t// from `using ii: InnerInner`\n\tfield: int,\n}")
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

	test.expect_hover(t, &source, "// do foo\ntest.foo: proc()\n doc")
}

@(test)
ast_hover_proc_comments_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package

			foo :: proc() { // do foo

			}

		`,
		},
	)
	source := test.Source {
		main = `package main
		import "my_package"

		main :: proc() {
			my_package.fo{*}o()
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "// do foo\nmy_package.foo: proc()")
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
