package tests

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

	test.expect_hover(t, &source, "test.My_Struct :: struct {\n\tproperty: int,\n}")
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
		"test.procedure :: proc(called_from: Expr_Called_Type = .None, options := List_Options{})",
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

	test.expect_hover(t, &source, "test.cool: my_package.My_Struct")
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

	test.expect_hover(t, &source, "test.cool: ^my_package.My_Struct")
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

	test.expect_hover(t, &source, "test.fa :: #type proc(color_: Color = {255, 255, 255, 255})")
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

	test.expect_hover(t, &source, "test.Vec :: [2]f32")
}

@(test)
ast_hover_on_array_infer_length_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		ve{*}c :: [?]f32{1, 2, 3}
		`,
	}

	test.expect_hover(t, &source, "test.vec :: [?]f32{1, 2, 3}")
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

	test.expect_hover(t, &source, "my_package.My_Struct :: struct {\n\tone:   int,\n\ttwo:   int,\n\tthree: int,\n}")
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

	test.expect_hover(t, &source, "my_package.my_package :: proc() -> int")
}


@(test)
ast_hover_proc_group :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		add_num :: proc(a, b: int) -> int {return a + b}

		add_vec :: proc(a, b: [2]f32) -> [2]f32 {return a + b}

		// docs
		add :: proc { // comment
			add_num,
			add_vec,
		}
		main :: proc() {
			foo := ad{*}d(2, 2)
		}	

		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.add :: proc(a, b: int) -> int\n---\ndocs\n---\ncomment")
}

@(test)
ast_hover_proc_with_proc_parameter :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		a{*}a :: proc(p: proc()) {}
		`,
	}

	test.expect_hover(t, &source, "test.aa :: proc(p: proc())")
}

@(test)
ast_hover_proc_with_proc_parameter_with_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		a{*}a :: proc(p: proc() -> int) {}
		`,
	}

	test.expect_hover(t, &source, "test.aa :: proc(p: proc() -> int)")
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
		"test.Foo :: struct {\n\t// this is a doc\n\tbar: int,\n\tf:   proc(a: int) -> int,\n}",
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

	test.expect_hover(t, &source, "my_package.My_Struct :: struct {\n\tone:   int,\n\ttwo:   int,\n\tthree: int,\n}")
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

	test.expect_hover(t, &source, "test.foo: test.Foo")
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

	test.expect_hover(t, &source, "test.Foo :: enum {\n\tFoo1,\n\tFoo2,\n}")
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

	test.expect_hover(t, &source, "test.foo: test.Foo")
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

	test.expect_hover(t, &source, "test.Foo :: union {\n\tstring,\n\tint,\n}")
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

	test.expect_hover(t, &source, "test.foo: test.Foo")
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

	test.expect_hover(t, &source, "Foo.bar: ^test.Bar\n---\nDocs\n---\ninline docs")
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

	test.expect_hover(t, &source, "test.get_int :: proc() -> int")
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
		"test.foo :: proc(i: int, j: int, allocator := context.allocator) -> (_: int, _: bool)",
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

	test.expect_hover(t, &source, "test.foo :: proc(allocator := context.allocator) -> (_: int, _: bool)")
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

	test.expect_hover(t, &source, "test.foo :: proc(i: int, s := \"hello\") -> (_: int, _: bool)")
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
		"my_package.foo :: proc(i: int, allocator := context.allocator, loc := #caller_location) -> (_: int, _: bool)",
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
		"test.foo :: proc {\n\tfoo_none :: proc(allocator := context.allocator) -> (_: int, _: bool),\n\tfoo_int :: proc(i: int, allocator := context.allocator) -> (_: int, _: bool),\n}",
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

	test.expect_hover(t, &source, "test.Foo :: struct {\n\tbar: int,\n}")
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

	test.expect_hover(t, &source, "test.foo :: proc(i: int)")
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
		// Docs
		foo :: proc { // comment
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

	test.expect_hover(t, &source, "my_package.foo :: proc(x := 1) -> (_: int, _: bool)\n---\nDocs\n---\ncomment")
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

	test.expect_hover(t, &source, "my_package.foo :: proc(x := 1) -> (_: int, _: bool)")
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

	test.expect_hover(t, &source, "my_package.foo :: proc(x := 1) -> (_: int, _: bool)")
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

	test.expect_hover(t, &source, "my_package.Foo :: struct {\n\tfoo: string,\n}")
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

	test.expect_hover(t, &source, "my_package.Foo :: struct {\n\tfoo: string,\n}")
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

	test.expect_hover(t, &source, "test.foo: ^my_package.Foo")
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

	test.expect_hover(t, &source, "test.foo: ^my_package.Foo")
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
		"test.Foo :: struct {\n\t// This is an int\n\tfoo_int: int,\n\tbar:     int, // this is bar\n\tbazz:    int,\n}",
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
		"test.Bazz :: struct {\n\tusing bar:  Bar,\n\n\t// from `using bar: Bar`\n\t// using a foo\n\tusing foo:  Foo, // hi\n\t// this is a string\n\tbar_string: string,\n\tbar_int:    int, // This is a bar int\n\n\t// from `using foo: Foo`\n\t// This is an int\n\tfoo_int:    int,\n\tfoo_string: string,\n}",
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
		"test.Foo :: struct {\n\tusing outer: my_package.Outer,\n\n\t// from `using outer: my_package.Outer`\n\t// Inner doc\n\tusing inner: Inner,\n\n\t// from `using inner: Inner`\n\tusing ii:    InnerInner, // InnerInner comment\n\n\t// from `using ii: InnerInner`\n\tfield:       int,\n}",
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

	test.expect_hover(t, &source, "test.foo :: proc()\n---\ndoc\n---\ndo foo")
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

	test.expect_hover(t, &source, "my_package.foo :: proc()\n---\ndo foo")
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

	test.expect_hover(t, &source, "S.fb: test.B\n---\ntype: fb")
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

	test.expect_hover(t, &source, "test.A :: distinct u64")
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

	test.expect_hover(t, &source, "my_package.A :: distinct u64")
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

	test.expect_hover(t, &source, "test.foo: test.Foo")
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

	test.expect_hover(t, &source, "test.foo: test.Foo")
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

	test.expect_hover(t, &source, "test.foo: small_array.Foo")
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

	test.expect_hover(t, &source, "test.Foo :: struct($T: typeid) {\n\tfoo: T,\n}")
}

@(test)
ast_hover_struct_poly_type_external_package :: proc(t: ^testing.T) {
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

		fo{*}os: small_array.Small_Array(MAX, Foo)
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "test.foos: small_array.Small_Array(MAX, Foo)")
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

	test.expect_hover(t, &source, "test.f: bar_package.Bar")
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
		"test.Foo :: struct($S: typeid, $T: typeid) {\n\tmy_proc1: proc(s: S) -> ^S,\n\tmy_proc2: proc(t: ^T) -> T,\n\tmy_proc3: proc(s: ^S, t: T) -> T,\n\tmy_proc4: proc() -> T,\n\tmy_proc5: proc(t: T),\n\tfoo1:     T,\n\tfoo2:     ^S,\n}",
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
		"test.Foo :: struct(Bar, my_package.Bazz) {\n\tmy_proc1: proc(s: Bar) -> ^Bar,\n\tmy_proc2: proc(t: my_package.Bazz) -> my_package.Bazz,\n\tmy_proc3: proc(s: ^my_package.Bazz, t: my_package.Bazz) -> my_package.Bazz,\n\tfoo1:     my_package.Bazz,\n\tfoo2:     ^Bar,\n}",
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
	test.expect_hover(t, &source, "test.f: test.Foo")
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
	test.expect_hover(t, &source, "test.Foo :: enum u8 {\n\tA   = 1,\n\tBar = 2,\n\tC   = 3,\n}")
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
	test.expect_hover(t, &source, "test.Foo :: bit_field u8 {\n\tfoo_a:  uint | 2,\n\tfoo_aa: uint | 4,\n}")
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
	test.expect_hover(t, &source, "test.Foo :: bit_field [4]u8 {\n\tfoo_a:  uint | 1,\n\tfoo_aa: uint | 3,\n}")
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
		"test.Foo :: bit_field u8 {\n\t// documentation\n\tfoo_a:    uintptr | 2,\n\tfoo_bbbb: uint    | 4, // comment for b\n\t// doc\n\tfoo_c:    uint    | 2, //comment\n}",
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
		"test.Bar :: struct {\n\tusing foo: Foo,\n\tbar:       int,\n\n\t// from `using foo: Foo (bit_field u8)`\n\tfoo_a:     uint | 2, // foo_a\n\t// foo_aa\n\tfoo_aa:    uint | 4,\n}",
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
		"test.Bar :: struct {\n\tusing foo:  my_package.Foo,\n\tusing bazz: Bazz,\n\tbar:        int,\n\n\t// from `using foo: my_package.Foo (bit_field u8)`\n\tfoo_a:      uint           | 1, // foo_a\n\t// foo_aa\n\tfoo_aa:     uint           | 7,\n\n\t// from `using bazz: Bazz`\n\tbazz:       string, // string for bazz\n}",
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
	test.expect_hover(t, &source, "Foo.foo_aa: uint | 6\n---\nlast 6 bits")
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
	test.expect_hover(t, &source, "Foo.foo_a: uint | 2\n---\ndoc\n---\nfoo a")
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
	test.expect_hover(t, &source, "Bar.foo: test.Foo")
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
	test.expect_hover(t, &source, "test.Bar :: struct {\n\tbar: int,\n}")
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
		test.Package{pkg = "str", source = `package str
			get_str :: proc() -> string {
				return "foo"
			}
		`},
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
	test.expect_hover(t, &source, "my_package.foo :: proc(a: string, b: int)")
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
	test.expect_hover(t, &source, "Foo.a: int\n---\na docs\n---\na comment")
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
	test.expect_hover(t, &source, "Foo.a: int\n---\na docs\n---\na comment")
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
	test.expect_hover(t, &source, "Foo.bar: test.Bar\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: proc(a: int) -> int\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: proc(a: int) -> string\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: map[int]int\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: bit_set[0 ..< 10]\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: test.Bar\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: [^]int\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: [dynamic]int\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: [5]int\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "Foo.bar: matrix[4,5]int\n---\nbar docs\n---\nbar comment")
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
	test.expect_hover(t, &source, "foo.a: test.Bar")
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
	test.expect_hover(t, &source, "test.my_overload :: proc(fb: FooBar)")
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
	test.expect_hover(t, &source, "test.my_overload :: proc(bar: Bar)")
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
	test.expect_hover(t, &source, "test.foobar :: proc(b: Bar)")
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
	test.expect_hover(t, &source, "test.foobar :: proc(b: ^Bar)")
}

@(test)
ast_hover_proc_calling_convention :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc "contextless" (a: int) {}
	`,
	}
	test.expect_hover(t, &source, "test.foo :: proc \"contextless\" (a: int)")
}

@(test)
ast_hover_proc_directives :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc(a: int) #no_bounds_check {}
	`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(a: int) #no_bounds_check")
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
	test.expect_hover(t, &source, "@(require_results)\ntest.foo :: proc(a: int) -> int")
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
	test.expect_hover(t, &source, "@(disabled=false)\ntest.foo :: proc(a: int) -> int")
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
	test.expect_hover(t, &source, "test.foo :: #force_inline proc(a: int) -> int")
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
	test.expect_hover(t, &source, "test.foo :: #force_no_inline proc(a: int) -> int")
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
	test.expect_hover(t, &source, "test.max_u32 :: u32")
}

@(test)
ast_hover_builtin_max_with_type_global :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		ma{*}x_u32 :: max(u32)
	`,
	}
	test.expect_hover(t, &source, "test.max_u32 :: max(u32)")
}

@(test)
ast_hover_builtin_max_ints :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		ma{*}x_int :: max(1, 2, 3, 4)
	`,
	}
	test.expect_hover(t, &source, "test.max_int :: max(1, 2, 3, 4)")
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
	test.expect_hover(t, &source, "test.m :: max(1, 2.0, 3, 4.6)")
}

@(test)
ast_hover_builtin_max_mix_global_const :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		m{*} :: max(1, 2.0, 3, 4.6)
	`,
	}
	test.expect_hover(t, &source, "test.m :: max(1, 2.0, 3, 4.6)")
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
ast_hover_builtin_max_f32 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			a := f32(0)
			b := f32(1)
			m{*} := max(a, b)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: f32")
}

@(test)
ast_hover_builtin_max_global_consts :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		a :: 0.0
		b :: 1.0

		main :: proc() {
			m{*} := max(a, b)
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
ast_hover_builtin_abs :: proc(t: ^testing.T) {
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
ast_hover_builtin_clamp_less :: proc(t: ^testing.T) {
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
ast_hover_builtin_clamp_greater :: proc(t: ^testing.T) {
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
ast_hover_builtin_clamp_between :: proc(t: ^testing.T) {
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
ast_hover_builtin_clamp_from_proc :: proc(t: ^testing.T) {
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
ast_hover_builtin_complex :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			m{*} := complex(1, 2)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: complex128")
}

@(test)
ast_hover_builtin_complex_with_global_const :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		a :: 0
		b :: 1

		main :: proc() {
			m{*} := complex(a, b)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: complex128")
}

@(test)
ast_hover_builtin_complex_variables :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			a := f32(1)
			b := f32(2)
			m{*} := complex(a, b)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: complex64")
}

@(test)
ast_hover_builtin_quaternion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			m{*} := quaternion(w = 1, x = 2, y = 3, z = 4)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: quaternion256")
}

@(test)
ast_hover_builtin_quaternion_with_global_const :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		w :: 0
		x :: 1
		y :: 1
		z :: 1

		main :: proc() {
			m{*} := quaternion(w = w, x = x, y = y, z = z)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: quaternion256")
}

@(test)
ast_hover_builtin_quaternion_variables :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			a := f16(1)
			b := f16(2)
			c := f16(2)
			d := f16(2)
			m{*} := quaternion(w = a, x = b, y = c, z = d)
		}
	`,
	}
	test.expect_hover(t, &source, "test.m: quaternion64")
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
	test.expect_hover(t, &source, "my_package.Foo :: struct{}\n---\nDocumentation for Foo")
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
	test.expect_hover(t, &source, "my_package.Foo :: struct{}\n---\nNew docs for Foo")
}

@(test)
ast_hover_switch_initialiser :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		A :: enum { B, C }

		main :: proc() {
			a : A
			b : []A

			switch c := b[0]; c{*} {
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.c: test.A")
}

@(test)
ast_hover_type_switch_with_using :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			Foo :: struct{}
			Bar :: struct{}
			Foo_Bar :: union {
				^Foo,
				^Bar,
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		foo :: proc(fb: ^my_package.Foo_Bar) {
			using my_package
			#partial switch v in fb {
			case ^Foo:
				v{*}
			}
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "test.v: ^my_package.Foo")
}

@(test)
ast_hover_union_with_poly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: union($T: typeid) {
			T,
		}

		main :: proc() {
			fo{*}o: Foo(int)
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: test.Foo(int)")
}

@(test)
ast_hover_union_with_poly_from_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "my_package", source = `package my_package

			Foo :: union($T: typeid) {
				T,
			}
		`},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			fo{*}o: my_package.Foo(int)
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "test.foo: my_package.Foo(int)")
}

@(test)
ast_hover_overloaded_proc_with_u8_byte_alias :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo_str :: proc(s: string) -> string {
			return s
		}

		foo_bytes :: proc(b: []u8) -> []u8 {
			return b
		}

		foo :: proc {
			foo_str,
			foo_bytes,
		}

		main :: proc() {
			b: []byte
			res{*}ult := foo(b)
		}
		`,
	}
	test.expect_hover(t, &source, "test.result: []u8")
}

@(test)
ast_hover_chained_proc_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			someData: int,
		}

		main :: proc() {
			a{*} := foo()({})
		}

		foo :: proc() -> proc(data: Foo) -> bool {
			return bar
		}

		bar :: proc(data: Foo) -> bool {
			return false
		}
		`,
	}
	test.expect_hover(t, &source, "test.a: bool")
}

@(test)
ast_hover_chained_proc_call_multiple_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			someData: int,
		}

		main :: proc() {
			a, b{*} := foo()({})
		}

		foo :: proc() -> proc(data: Foo) -> (int, bool) {
			return bar
		}

		bar :: proc(data: Foo) -> (int, bool) {
			return 1, false
		}
		`,
	}
	test.expect_hover(t, &source, "test.b: bool")
}

@(test)
ast_hover_chained_call_expr_with_named_proc_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			someData: int,
		}

		main :: proc() {
			a, b{*} := foo()({})
		}

		Bar :: proc(data: Foo) -> (bool, Foo)

		foo :: proc() -> Bar {
			return bar
		}

		bar :: proc(data: Foo) -> (bool, Foo) {
			return false, data
		}
		`,
	}
	test.expect_hover(t, &source, "test.b: test.Foo")
}

@(test)
ast_hover_multiple_chained_call_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			someData: int,
		}

		Bazz :: struct {
			bazz: string,
		}

		main :: proc() {
			a{*} := foo()({})({})
		}

		Bar :: proc(data: Foo) -> Bar2

		Bar2 :: proc(bazz: Bazz) -> int

		foo :: proc() -> Bar {}
		`,
	}
	test.expect_hover(t, &source, "test.a: int")
}

@(test)
ast_hover_enum_field_documentation :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: enum {
			A = 1, // this is a comment for A
			// This is a doc for B
			// across many lines
			B,
			C,
			// D Doc
			D,
			E, // E comment
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: enum {\n\tA = 1, // this is a comment for A\n\t// This is a doc for B\n\t// across many lines\n\tB,\n\tC,\n\t// D Doc\n\tD,\n\tE, // E comment\n}",
	)
}

@(test)
ast_hover_enum_field_documentation_same_line :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: enum {
			// Doc for A and B
			// Mulitple lines!
			A, B, // comment for A and B
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: enum {\n\t// Doc for A and B\n\t// Mulitple lines!\n\tA, // comment for A and B\n\t// Doc for A and B\n\t// Mulitple lines!\n\tB, // comment for A and B\n}",
	)
}

@(test)
ast_hover_enum_field_directly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			// Doc for A and B
			// Mulitple lines!
			A{*}, B, // comment for A and B
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A\n---\nDoc for A and B\nMulitple lines!\n---\ncomment for A and B")
}

@(test)
ast_hover_union_field_documentation :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: union {
			int, // this is a comment for int
			// This is a doc for string
			// across many lines
			string,
			i16,
			// i32 Doc
			i32,
			i64, // i64 comment
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: union {\n\tint, // this is a comment for int\n\t// This is a doc for string\n\t// across many lines\n\tstring,\n\ti16,\n\t// i32 Doc\n\ti32,\n\ti64, // i64 comment\n}",
	)
}

@(test)
ast_hover_union_field_documentation_same_line :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: union {
			// Doc for int and string
			// Mulitple lines!
			int, string, // comment for int and string
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: union {\n\t// Doc for int and string\n\t// Mulitple lines!\n\tint, // comment for int and string\n\t// Doc for int and string\n\t// Mulitple lines!\n\tstring, // comment for int and string\n}",
	)
}

@(test)
ast_hover_parapoly_proc_dynamic_array_elems :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(array: $A/[dynamic]^$T) {
			for e{*}lem, i in array {

			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.elem: ^$T")
}

@(test)
ast_hover_parapoly_proc_slice_param :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(x: $T) -> T {
			return x
		}

		main :: proc() {
			x : []u8
			b{*}ar := foo(x)
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: []u8")
}

@(test)
ast_hover_parapoly_proc_multi_pointer_param :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(x: ^$T) -> ^T {
			return x
		}


		main :: proc() {
			x : [^]u8
			b{*}ar := foo(x)
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: ^[^]u8")
}

@(test)
ast_hover_union_with_tag :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: union #no_nil {
			int, string,
		}
		`,
	}

	test.expect_hover(t, &source, "test.Foo :: union #no_nil {\n\tint,\n\tstring,\n}")
}

@(test)
ast_hover_union_with_align :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: union #no_nil #align(4) {
			int, string,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: union #no_nil #align(4) {\n\tint,\n\tstring,\n}")
}

@(test)
ast_hover_bit_set_intersection :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Flag  :: enum u8 {Foo, Bar}
		Flags :: distinct bit_set[Flag; u8]

		foo_bar  := Flags{.Foo, .Bar} // foo_bar: bit_set[Flag]
		foo_{*}b := foo_bar & {.Foo}  // hover for foo_b
		`,
	}
	test.expect_hover(t, &source, "test.foo_b: distinct bit_set[Flag]\n---\nhover for foo_b")
}

@(test)
ast_hover_bit_set_union :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Flag  :: enum u8 {Foo, Bar}
		Flags :: distinct bit_set[Flag; u8]

		foo_bar  := Flags{.Bar} // foo_bar: bit_set[Flag]
		foo_{*}b := {.Foo} | foo_bar  // hover for foo_b
		`,
	}
	test.expect_hover(t, &source, "test.foo_b: distinct bit_set[Flag]\n---\nhover for foo_b")
}

@(test)
ast_hover_binary_expr_not_eq :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			fo{*}o := 1 != 2
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: bool")
}

@(test)
ast_hover_bit_set_in :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {A, B}

		main :: proc() {
			foos: bit_set[Foo]
			f{*}oo := .A in foos
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: bool")
}

@(test)
ast_hover_nested_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct {
			foo: int,
			bar: struct {
				i: int,
				s: string,
			}
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: struct {\n\tfoo: int,\n\tbar: struct {\n\t\ti: int,\n\t\ts: string,\n\t},\n}",
	)
}

@(test)
ast_hover_nested_struct_union :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct {
			foo: int,
			bar: union #no_nil {
				int, // int comment
				string,
			}
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: struct {\n\tfoo: int,\n\tbar: union #no_nil {\n\t\tint, // int comment\n\t\tstring,\n\t},\n}",
	)
}

@(test)
ast_hover_nested_struct_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct {
			foo: int,
			bar: enum {
				// A doc
				A,
				B,
			}
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: struct {\n\tfoo: int,\n\tbar: enum {\n\t// A doc\n\t\tA,\n\t\tB,\n\t},\n}",
	)
}

@(test)
ast_hover_nested_struct_bit_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct {
			foo: int,
			bar: bit_field u8 {
				// A doc
				a: uint | 3,
				b: uint | 5,
			}
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: struct {\n\tfoo: int,\n\tbar: bit_field u8 {\n\t// A doc\n\t\ta: uint | 3,\n\t\tb: uint | 5,\n\t},\n}",
	)
}

@(test)
ast_hover_foreign_block_calling_convention :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foreign import lib "lib"

		@(default_calling_convention="c")
		foreign lib {
			foo :: proc () -> int ---
		}

		fo{*}o
		`,
	}
	test.expect_hover(t, &source, `test.foo :: proc "c" () -> int`)
}

@(test)
ast_hover_foreign_block_calling_convention_overridden :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foreign import lib "lib"

		@(default_calling_convention="c")
		foreign lib {
			foo :: proc "contextless" () -> int ---
		}

		fo{*}o
		`,
	}
	test.expect_hover(t, &source, `test.foo :: proc "contextless" () -> int`)
}

@(test)
ast_hover_foreign_block_link_prefix :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foreign import lib "lib"

		@(link_prefix="bar")
		foreign lib {
			foo :: proc() -> int ---
		}

		fo{*}o
		`,
	}
	test.expect_hover(t, &source, "@(link_prefix=\"bar\")\ntest.foo :: proc() -> int")
}

@(test)
ast_hover_foreign_block_link_prefix_overridden :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foreign import lib "lib"

		@(link_prefix="bar")
		foreign lib {
			@(link_name="foreign_foo") foo :: proc() -> int ---
		}

		fo{*}o
		`,
	}
	test.expect_hover(t, &source, "@(link_name=\"foreign_foo\")\ntest.foo :: proc() -> int")
}

@(test)
ast_hover_foreign_private_block :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foreign import lib "lib"

		@(private)
		foreign lib {
			foo :: proc() -> int ---
		}

		fo{*}o
		`,
	}
	test.expect_hover(t, &source, "@(private)\ntest.foo :: proc() -> int")
}

@(test)
ast_hover_foreign_private_block_overridden :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foreign import lib "lib"

		@(private)
		foreign lib {
			@(private="file") foo :: proc() -> int ---
		}

		fo{*}o
		`,
	}
	test.expect_hover(t, &source, "@(private=\"file\")\ntest.foo :: proc() -> int")
}

@(test)
ast_hover_proc_return_types :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> (a, b: int, c: bool) {
			return
		}

		main :: proc() {
			a, b{*}, c := foo()
		}
		`,
	}
	test.expect_hover(t, &source, "test.b: int")
}

@(test)
ast_hover_proc_return_types_in_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> (a, b: int, c: bool) {
			return 1, 2, true
		}

		main :: proc() {
			for a, b{*} in foo() {

			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.b: int")
}

@(test)
ast_hover_proc_overloads_arrays :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		normalize2 :: proc (v: [2]f32) -> [2]f32 {return {}}
		normalize3 :: proc (v: [3]f32) -> [3]f32 {return {}}
		normalize  :: proc {normalize2, normalize3}

		main :: proc() {
			v3: [3]f32
			n{*}3 := normalize(v3)
		}
		`,
	}
	test.expect_hover(t, &source, "test.n3: [3]f32")
}

@(test)
ast_hover_map_empty_struct_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		m{*}: map[int]struct{}
		`,
	}
	test.expect_hover(t, &source, "test.m: map[int]struct{}")
}

@(test)
ast_hover_struct_container_fields :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: struct {
			foo_slice: []int,
			foo_dynamic: [dynamic]int,
			foo_array: [5]int,
			foo_map: map[int]int,
			foo_matrix: matrix[3,4]int,
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: struct {\n\tfoo_slice:   []int,\n\tfoo_dynamic: [dynamic]int,\n\tfoo_array:   [5]int,\n\tfoo_map:     map[int]int,\n\tfoo_matrix:  matrix[3,4]int,\n}",
	)
}

@(test)
ast_hover_struct_field_proc_calling_convention :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: struct {
			foo_proc: proc "c" (a: int, b: int) -> int,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: struct {\n\tfoo_proc: proc \"c\" (a: int, b: int) -> int,\n}")
}

@(test)
ast_hover_distinct_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}oo :: distinct [4]u8
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: distinct [4]u8")
}

@(test)
ast_hover_struct_tags :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct #no_copy #raw_union {
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: struct #raw_union #no_copy {}")
}

@(test)
ast_hover_struct_tags_packed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct($T: typeid) #packed #all_or_none {
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: struct($T: typeid) #packed #all_or_none {}")
}

@(test)
ast_hover_struct_tags_align :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct($T: typeid) #align(4) {
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: struct($T: typeid) #align(4) {}")
}

@(test)
ast_hover_struct_tags_align_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			Foo :: struct($T: typeid) #align(4) {
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			foo := my_package.F{*}oo(int){}
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.Foo :: struct(int) #align(4) {}")
}

@(test)
ast_hover_struct_tags_field_align :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Fo{*}o :: struct #max_field_align(4) #min_field_align(2) {
			
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: struct #max_field_align(4) #min_field_align(2) {}")
}

@(test)
ast_hover_soa_slice :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			f{*}oos: #soa[]Foo
		}
		`,
	}
	test.expect_hover(t, &source, "test.foos: #soa[]Foo")
}

@(test)
ast_hover_struct_with_soa_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		B{*}ar :: struct {
			foos: #soa[5]Foo,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Bar :: struct {\n\tfoos: #soa[5]Foo,\n}")
}

@(test)
ast_hover_soa_slice_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			foos: #soa[]Foo
			foos.x{*}
		}
		`,
	}
	test.expect_hover(t, &source, "foos.x: [^]int")
}

@(test)
ast_hover_identifier_soa_slice_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			foos: #soa[]Foo
			x{*} := foos.x
		}
		`,
	}
	test.expect_hover(t, &source, "test.x: [^]int")
}

@(test)
ast_hover_soa_fixed_array_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			foos: #soa[6]Foo
			foos.x{*}
		}
		`,
	}
	test.expect_hover(t, &source, "foos.x: [6]int")
}

@(test)
ast_hover_soa_pointer :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			f{*}oo: #soa^#soa[6]Foo
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: #soa^#soa[6]Foo")
}

@(test)
ast_hover_soa_pointer_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			foo: #soa^#soa[6]Foo
			foo.x{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.x: int")
}

@(test)
ast_hover_proc_within_for_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			for true {
				f{*}oo :: proc() {}
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc()")
}

@(test)
ast_hover_string_slice_range :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: string
			ba{*}r := foo[1:2]
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: string")
}

@(test)
ast_hover_string_index :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: string
			ba{*}r := foo[1]
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: u8")
}

@(test)
ast_hover_untyped_string_index :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo := "hellope"
			ba{*}r := foo[1]
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: u8")
}

@(test)
ast_hover_multi_pointer_slice_end_range :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: [^]int
			b{*}ar := foo[:1]
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: []int")
}

@(test)
ast_hover_multi_pointer_slice_start_range :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: [^]int
			b{*}ar := foo[1:]
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: [^]int")
}

@(test)
ast_hover_multi_pointer_slice_no_range :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: [^]int
			b{*}ar := foo[:]
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: [^]int")
}

@(test)
ast_hover_binary_expr_with_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}OO :: 1 + u8(2)
		`,
	}
	test.expect_hover(t, &source, "test.FOO :: 1 + u8(2)")
}

@(test)
ast_hover_soa_pointer_field_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			Shape :: struct{a, b:int}
			ptr: #soa^#soa[]Shape

			a{*} := ptr.a
		}
		`,
	}
	test.expect_hover(t, &source, "test.a: int")
}

@(test)
ast_hover_overload_private_procs :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package

			@(private = "file")
			foo_str :: proc(s: string) {}
			@(private = "file")
			foo_int :: proc(i: int) {}
			foo :: proc {
				foo_str,
				foo_int,
			}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			s: string
			foo := my_package.fo{*}o(s)
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "@(private=\"file\")\nmy_package.foo :: proc(s: string)")
}

@(test)
ast_hover_keyword_transmute :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			foo: f64
			bar := trans{*}mute(i64)foo
		}
		`,
	}
	test.expect_hover(t, &source, "transmute(T)v\nBitwise cast between 2 types of the same size.")
}

@(test)
ast_hover_ternary :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		fo{*}o :: true ? 1 : 2
		`,
	}
	test.expect_hover(t, &source, "test.foo :: 1")
}

@(test)
ast_hover_defer_statement :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc() {
			defer {
				s{*}: struct {
					bar: int,
				}
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.s: struct {\n\tbar: int,\n}")
}

@(test)
ast_hover_implicit_selector_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: enum {
			A,
			B,
		}

		main :: proc(foo: Foo) -> Bar {
			switch foo {
			case .A:
				return .A{*}
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Bar: .A")
}

@(test)
ast_hover_basic_value_cast_from_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bar :: int
		`})
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			foo := i64(1)
			b{*}ar := my_package.Bar(foo)
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "test.bar: my_package.Bar")
}

@(test)
ast_hover_parapoly_elem_overloaded_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc {
			foo_array,
			foo_int,
		}

		foo_int :: proc(i: int) {}

		foo_array :: proc(array: $A/[]$T) {
			for elem in array {
				f{*}oo(elem)
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(i: int)")
}

@(test)
ast_hover_parapoly_elem_overloaded_proc_multiple_options :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc {
			foo_array,
			foo_int,
			foo_string,
		}

		foo_int :: proc(i: int) {}
		foo_string :: proc(s: string) {}

		foo_array :: proc(array: $A/[]$T) {
			for elem in array {
				f{*}oo(elem)
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc {\n\tfoo_int :: proc(i: int),\n\tfoo_string :: proc(s: string),\n}")
}

@(test)
ast_hover_overloaded_proc_slice_dynamic_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc {
			foo_slice,
			foo_dynamic,
		}

		foo_dynamic :: proc(array: $A/[dynamic]$T) {}
		foo_slice :: proc(array: $A/[]$T) {}

		main :: proc() {
			foos: [dynamic]int
			f{*}oo(foos)
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(array: $A/[dynamic]$T)")
}

@(test)
ast_hover_proc_call_implicit_selector_with_default_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			X, Y,
		}

		Option :: enum {
			A,
			B,
		}

		Options :: distinct bit_set[Option]

		foo :: proc(options := Options{}) {
		}

		main :: proc() {
			foo({.A, .B{*}})
		}
		`,
	}
	test.expect_hover(t, &source, "test.Option: .B")
}

@(test)
ast_hover_casted_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: int = 25
			bar := cast(f32)fo{*}o
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: int")
}

@(test)
ast_hover_float_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo := 2.1
			b{*}ar := foo - 2
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: f64")
}

@(test)
ast_hover_parapoly_struct_with_where_clause :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		type_is_integer :: proc($T: typeid) -> bool {
			return true
		}

		F{*}oo :: struct($T: typeid, $N: int) #packed
			where type_is_integer(T),
				  N > 2 {
			x: [N]T,
			y: [N-2]T,
		}
		`,
	}
	test.expect_hover(
		t,
		&source,
		"test.Foo :: struct($T: typeid, $N: int) #packed where type_is_integer(T), N > 2 {\n\tx: [N]T,\n\ty: [N - 2]T,\n}",
	)
}

@(test)
ast_hover_parapoly_proc_with_where_clause :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		fo{*}o :: proc(x: [$N]int) -> bool
			where N > 2 #optional_ok {
			fmt.println(#procedure, "was called with the parameter", x)
			return true
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(x: [$N]int) -> bool where N > 2 #optional_ok")
}

@(test)
ast_hover_parapoly_union_with_where_clause :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		type_is_integer :: proc($T: typeid) -> bool {
			return true
		}

		Fo{*}o :: union($T: typeid) #no_nil where type_is_integer(T){
			T,
			string,
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo :: union($T: typeid) #no_nil where type_is_integer(T) {\n\tT,\n\tstring,\n}")
}

@(test)
ast_hover_proc_named_return_parens :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc() -> (a: int) {
			return
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc() -> (a: int)")
}

@(test)
ast_hover_map_value_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: int,
		}

		main :: proc() {
			m: map[int]Foo
			m[0] = {
				f{*}oo = 1,
			}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.foo: int")
}

@(test)
ast_hover_assign_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: int,
		}

		main :: proc() {
			foo: Foo
			foo = {
				f{*}oo = 1,
			}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.foo: int")
}

@(test)
ast_hover_assign_comp_lit_with_multiple_assigns_first :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
		}

		Bar :: struct {
			b: int,
		}

		main :: proc() {
			foo: Foo
			bar: Bar

			foo, bar = {a{*} = 1}, {b = 2}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.a: int")
}

@(test)
ast_hover_assign_comp_lit_with_multiple_assigns_second :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
		}

		Bar :: struct {
			b: int,
		}

		main :: proc() {
			foo: Foo
			bar: Bar

			foo, bar = {a = 1}, {b{*} = 2}
		}
		`,
	}
	test.expect_hover(t, &source, "Bar.b: int")
}

@(test)
ast_hover_comp_lit_map_key :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
		}

		Bar :: struct {
			b: int,
		}

		main :: proc() {
			m: map[Foo]Bar
			m[{a{*} = 1}] = {b = 2}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.a: int")
}

@(test)
ast_hover_inner_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			b: struct {
				c{*}: int,
			}
		}
		`,
	}
	test.expect_hover(t, &source, "struct.c: int")
}

@(test)
ast_hover_using_bit_field_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			using _: bit_field u8 {
				c{*}: u8 | 8,
			},
		}
		`,
	}
	test.expect_hover(t, &source, "bit_field.c: u8 | 8")
}

@(test)
ast_hover_proc_group_parapoly_matrix :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		mul :: proc {
			matrix_mul,
			matrix_mul_differ,
		}

		@(require_results)
		matrix_mul :: proc "contextless" (a, b: $M/matrix[$N, N]$E) -> (c: M)
			where !IS_ARRAY(E), IS_NUMERIC(E) #no_bounds_check {
			return a * b
		}

		@(require_results)
		matrix_mul_differ :: proc "contextless" (a: $A/matrix[$I, $J]$E, b: $B/matrix[J, $K]E) -> (c: matrix[I, K]E)
			where !IS_ARRAY(E), IS_NUMERIC(E), I != K #no_bounds_check {
			return a * b
		}

		main :: proc() {
			a: matrix[3,3]int
			b: matrix[3,2]int
			c{*} := mul(a, b)
		}
		`,
	}
	test.expect_hover(t, &source, "test.c: matrix[3,2]int")
}

@(test)
ast_hover_proc_group_variadic_args :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		append_elems :: proc(array: ^$T/[dynamic]string, args: ..string) {}
		append_elem :: proc(array: ^$T/[dynamic]string, arg: string) {}

		append :: proc {
			append_elem,
			append_elems,
		}

		main :: proc() {
			foos: [dynamic]string
			bars: [dynamic]string
			app{*}end(&bars, ..foos[:])
		}
		`,
	}
	test.expect_hover(t, &source, "test.append :: proc(array: ^$T/[dynamic]string, args: ..string)")
}

@(test)
ast_hover_proc_group_variadic_args_with_generic_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		append_elems :: proc(array: ^$T/[dynamic]$E, args: ..E) {}
		append_elem :: proc(array: ^$T/[dynamic]$E, arg: E) {}

		append :: proc {
			append_elem,
			append_elems,
		}

		main :: proc() {
			foos: [dynamic]string
			bars: [dynamic]string
			app{*}end(&bars, ..foos[:])
		}
		`,
	}
	test.expect_hover(t, &source, "test.append :: proc(array: ^$T/[dynamic]$E, args: ..E)")
}

@(test)
ast_hover_proc_group_with_generic_type_from_proc_param :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		append_elems :: proc(array: ^$T/[dynamic]$E, args: ..E) {}
		append_elem :: proc(array: ^$T/[dynamic]$E, arg: E) {}

		append :: proc {
			append_elem,
			append_elems,
		}

		foo :: proc(bars: ^[dynamic]string) {
			app{*}end(bars, "test")
		}
		`,
	}
	test.expect_hover(t, &source, "test.append :: proc(array: ^$T/[dynamic]$E, arg: E)")
}

@(test)
ast_hover_enum_implicit_if_statement :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			foo: Foo
			if foo == .A{*} {
			}
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}

@(test)
ast_hover_if_ternary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: []int
			ba{*}r := len(foo) if true else 2
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: int")
}

@(test)
ast_hover_proc_param_tags :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc (#by_ptr a: int, #any_int b: int) {}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(#by_ptr a: int, #any_int b: int)")
}

@(test)
ast_hover_simd_array :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		f{*}oo := #simd[2]f32{}
		`,
	}
	test.expect_hover(t, &source, "test.foo: #simd[2]f32")
}

@(test)
ast_hover_simd_array_pointer :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		f{*}oo := &#simd[4]f32{}
		`,
	}
	test.expect_hover(t, &source, "test.foo: ^#simd[4]f32")
}

@(test)
ast_hover_const_untyped_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}OO :: 123
		`,
	}
	test.expect_hover(t, &source, "test.FOO :: 123")
}

@(test)
ast_hover_const_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			b: string,
		}

		F{*}OO :: Foo {
			a = 1,
			b = "b",
		}
		`,
	}
	test.expect_hover(t, &source, "test.FOO :: Foo {\n\ta = 1,\n\tb = \"b\",\n}")
}

@(test)
ast_hover_const_comp_lit_with_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			b: string,
		}

		F{*}OO : Foo : {
			a = 1,
			b = "b",
		}
		`,
	}
	test.expect_hover(t, &source, "test.FOO : Foo : {\n\ta = 1,\n\tb = \"b\",\n}")
}

@(test)
ast_hover_const_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		F{*}OO :: 3 + 4
		`,
	}
	test.expect_hover(t, &source, "test.FOO :: 3 + 4")
}

@(test)
ast_hover_const_complex_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		frgba :: distinct [4]f32

		COLOUR_BLUE :: frgba{0.1, 0.1, 0.1, 0.1}

		Foo :: struct {
			a: int,
			b: string,
		}

		Colours :: struct {
			blue:  frgba,
			green: frgba,
			foo:   Foo,
			bar:   int,
		}

		COL{*}OURS :: Colours {
			blue = frgba{0.1, 0.1, 0.1, 0.1},
			green = frgba{0.1, 0.1, 0.1, 0.1},
			foo = {
				a = 32,
				b = "testing"
			},
			bar = 1 + 2,
		}
		`,
	}
	test.expect_hover(t, &source, "test.COLOURS :: Colours {\n\tblue = frgba{0.1, 0.1, 0.1, 0.1},\n\tgreen = frgba{0.1, 0.1, 0.1, 0.1},\n\tfoo = {\n\t\ta = 32,\n\t\tb = \"testing\",\n\t},\n\tbar = 1 + 2,\n}")
}

@(test)
ast_hover_proc_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc(a: int) -> int
		`,
	}
	test.expect_hover(t, &source, "test.foo :: #type proc(a: int) -> int")
}

@(test)
ast_hover_proc_impl :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc(a: int) -> int {
			return a + 1
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(a: int) -> int")
}

@(test)
ast_hover_proc_overload_generic_map :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		clear_dynamic_array :: proc "contextless" (array: ^$T/[dynamic]$E) {}
		clear_map :: proc "contextless" (m: ^$T/map[$K]$V) {}
		clear :: proc{
			clear_dynamic_array,
			clear_map,
		}
		main :: proc() {
			foo: map[int]string
			c{*}lear(&foo)
		}
		`,
	}
	test.expect_hover(t, &source, "test.clear :: proc(m: ^$T/map[$K]$V)")
}

@(test)
ast_hover_proc_overload_basic_type_alias :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bar :: int
		`})

	source := test.Source {
		main = `package test
		import "my_package"

		foo_int :: proc(i: int) {}
		foo_string :: proc(s: string) {}
		foo :: proc {
			foo_int,
			foo_string,
		}

		main :: proc() {
			bar: my_package.Bar
			f{*}oo(bar)
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "test.foo :: proc(i: int)")
}

@(test)
ast_hover_proc_overload_nil_pointer :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo_int :: proc(i: int) {}
		foo_ptr :: proc(s: ^string) {}
		foo :: proc {
			foo_int,
			foo_ptr,
		}

		main :: proc() {
			f{*}oo(nil)
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(s: ^string)")
}

@(test)
ast_hover_package_proc_naming_conflicting_with_another_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			foo :: proc() {}
		`,
		},
	)
	append(
		&packages,
		test.Package {
			pkg = "foo",
			source = `package foo
		`,
		},
	)

	source := test.Source {
		main     = `package test
		import "my_package"
		import "foo"

		main :: proc() {
			f := my_package.fo{*}o
		}
		`,
		packages = packages[:],
	}

	test.expect_hover(t, &source, "my_package.foo :: proc()")
}

@(test)
ast_hover_matrix_index :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: matrix[3, 2]f32
			a{*} := foo[0]
		}
		`,
	}
	test.expect_hover(t, &source, "test.a: [3]f32")
}

@(test)
ast_hover_matrix_index_twice :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: matrix[2, 3]f32
			a := foo[0]
			b{*} := a[0]
		}
		`,
	}
	test.expect_hover(t, &source, "test.b: f32")
}

@(test)
ast_hover_parapoly_proc_slice_param_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Iter :: struct(T: typeid) {
			slice: []T,
			index: int,
		}

		make_iter :: proc(slice: []$T) -> Iter(T) {
			return { slice, 0 }
		}

		main :: proc() {
			slice := []string{}
			i{*}t := make_iter(slice)
		}
		`,
	}
	test.expect_hover(t, &source, "test.it: test.Iter(string)")
}

@(test)
ast_hover_generic_proc_with_inlining :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Bar :: struct{}

		foo :: #force_inline proc(data: $T) {}

		main :: proc() {
			f{*}oo(Bar{})
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: #force_inline proc(data: $T)")
}

@(test)
ast_hover_using_import_statement_name_conflict :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bar :: struct {
				b: string,
			}
		`})

	source := test.Source {
		main = `package test
		import "my_package"

		Bar :: struct {
			a: int,
		}

		main :: proc() {
			using my_package
			bar := Ba{*}r{}
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "my_package.Bar :: struct {\n\tb: string,\n}")
}

@(test)
ast_hover_enum_in_bitset_within_call_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {A, B}
		Foos :: bit_set[Foo]

		bar :: proc(a: bool) {}

		main :: proc() {
			foos: Foos
			bar(.A{*} in foos)
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}

@(test)
ast_hover_typeid_with_specialization :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo{*} :: proc($T: typeid/[]$E) {}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc($T: typeid/[]$E)")
}

@(test)
ast_hover_proc_group_with_enum_arg :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
			C,
		}

		bar_none :: proc() {}
		bar_foo :: proc(foo: Foo) {}
		bar :: proc {
			bar_none,
			bar_foo,
		}

		main :: proc() {
			b{*}ar(.B)
		}

		`,
	}
	test.expect_hover(t, &source, "test.bar :: proc(foo: Foo)")
}

@(test)
ast_hover_proc_group_with_enum_named_arg :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
			C,
		}

		bar_none :: proc() {}
		bar_foo :: proc(i: int, foo: Foo) {}
		bar :: proc {
			bar_none,
			bar_foo,
		}

		main :: proc() {
			b{*}ar(foo = .B, i = 2)
		}

		`,
	}
	test.expect_hover(t, &source, "test.bar :: proc(i: int, foo: Foo)")
}

@(test)
ast_hover_proc_group_named_arg_with_nil :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {}

		bar_none :: proc() {}
		bar_foo :: proc(i: int, foo: ^Foo) {}
		bar :: proc {
			bar_none,
			bar_foo,
		}

		main :: proc() {
			b{*}ar(foo = nil, i = 2)
		}

		`,
	}
	test.expect_hover(t, &source, "test.bar :: proc(i: int, foo: ^Foo)")
}

@(test)
ast_hover_proc_return_with_union :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc() -> union{string, [4]u8} {}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc() -> union{string, [4]u8}")
}

@(test)
ast_hover_proc_return_with_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc() -> struct{s: string, i: int} {}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc() -> struct{s: string, i: int}")
}

@(test)
ast_hover_proc_return_with_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc() -> enum{A, B} {}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc() -> enum{A, B}")
}

@(test)
ast_hover_proc_arg_generic_bit_set :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		f{*}oo :: proc($T: typeid/bit_set[$F; $E]) {}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc($T: typeid/bit_set[$F; $E])")
}

@(test)
ast_hover_complex_number_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			f{*}oo := 1 + 1i
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: complex128")
}

@(test)
ast_hover_quaternion_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			f{*}oo := 1 + 2i + 3j + 4k
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: quaternion256")
}

@(test)
ast_hover_parapoly_other_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
		// Docs!
		bar :: proc(_: $T) {} // Comment!
		`})
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			my_package.ba{*}r("test")
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "my_package.bar :: proc(_: $T)\n---\nDocs!\n---\nComment!")
}

@(test)
ast_hover_local_const_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			f{*}oo :: 1 + 2
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo :: 1 + 2")
}

@(test)
ast_hover_local_const_binary_expr_with_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			f{*}oo : i32 : 1 + 2
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo : i32 : 1 + 2")
}

@(test)
ast_hover_loop_over_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {A, B, C}
		main :: proc() {
			for f{*}oo in Foo {}
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: test.Foo")
}

@(test)
ast_hover_parapoly_return_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {A, B, C}

		get :: proc($T: typeid) -> T {}

		main :: proc() {
			f{*}oo := get(Foo)
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: test.Foo")
}

@(test)
ast_hover_parapoly_return_union :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {int}

		get :: proc($T: typeid) -> T {}

		main :: proc() {
			f{*}oo := get(Foo)
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: test.Foo")
}

@(test)
ast_hover_parapoly_return_bit_set :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {int}

		get :: proc($T: typeid) -> T {}

		main :: proc() {
			f{*}oo := get(Foo)
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: test.Foo")
}

@(test)
ast_hover_parapoly_return_slice :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: []int

		get :: proc($T: typeid) -> T {}

		main :: proc() {
			f{*}oo := get(Foo)
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: []int")
}

@(test)
ast_hover_parapoly_return_dynamic_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: [dynamic]string

		get :: proc($T: typeid) -> T {}

		main :: proc() {
			f{*}oo := get(Foo)
		}

		`,
	}
	test.expect_hover(t, &source, "test.foo: [dynamic]string")
}

@(test)
ast_hover_proc_overload_with_less_args :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {}

		foo_out :: proc(input: int, out_struct: ^Foo) -> (ok: bool) {}
		foo_helper :: proc(input: int) -> (out_struct: Foo, ok: bool) {}

		foo :: proc {
			foo_out,
			foo_helper,
		}

		main :: proc() {
			some, ok := f{*}oo(1)
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc(input: int) -> (out_struct: Foo, ok: bool)")
}

@(test)
ast_hover_array_type_local_scope :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			Arra{*}y :: [2]int
		}
		`,
	}
	test.expect_hover(t, &source, "test.Array :: [2]int")
}

@(test)
ast_hover_array_elem_local_scope :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			Array :: [2]int
			array: Array
			f{*}oo := array[0]
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: int")
}

@(test)
ast_hover_array_of_array_type_x_elem_local_scope :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			Array :: [2]int
			Array_2 :: [2]Array
			array_2: Array_2
			f{*}oo := array_2.x
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: [2]int")
}

@(test)
ast_hover_soa_poly_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc (arr: ^#soa[dynamic]$E) -> #soa^#soa[dynamic]E {}

		main :: proc() {
			array: #soa[dynamic]struct{}
			b{*}ar := foo(&array)
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: #soa^#soa[dynamic]struct{}")
}

@(test)
ast_hover_slice_function_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> []int {}

		main :: proc() {
			x{*} := foo()[:1]
		}
		`,
	}
	test.expect_hover(t, &source, "test.x: []int")
}

@(test)
ast_hover_index_function_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> []int {}

		main :: proc() {
			x{*} := foo()[0]
		}
		`,
	}
	test.expect_hover(t, &source, "test.x: int")
}

@(test)
ast_hover_local_proc_docs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			// foo doc
			f{*}oo :: proc() {}
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc()\n---\nfoo doc")
}

@(test)
ast_hover_struct_using_with_parentheses :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			using bar: (struct { a: int }),
		}
		main :: proc() {
			foo: Foo
			foo.a{*}
		}
		`,
	}
	test.expect_hover(t, &source, "Foo.a: int")
}

@(test)
ast_hover_named_proc_arg_hover :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(bar: f32) {}

		main :: proc() {
			foo(b{*}ar=42)
		}
		`,
	}
	test.expect_hover(t, &source, "foo.bar: f32")
}

@(test)
ast_hover_unary_function_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> int {}

		main :: proc() {
			b{*}ar := -foo()
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: int")
}

@(test)
ast_hover_unary_overload_function_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo_int :: proc() -> int {}
		foo_string :: proc(s: string) -> string {}
		foo :: proc {
			foo_int,
			foo_string,
		}

		main :: proc() {
			b{*}ar := -foo()
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: int")
}

@(test)
ast_hover_negate_function_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> bool {}

		main :: proc() {
			b{*}ar := !foo()
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: bool")
}

@(test)
ast_hover_function_call_with_parens :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() -> bool {}

		main :: proc() {
			b{*}ar := (foo())
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: bool")
}

@(test)
ast_hover_bitshift_integer_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo: u16
			b{*}ar := 6 << foo
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: int")
}

@(test)
ast_hover_type_assertion_unary_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {
			int,
			f64,
		}

		main :: proc() {
			foo := Foo(0.0)
			i{*} := &foo.(int)
		}
		`,
	}
	test.expect_hover(t, &source, "test.i: ^int")
}

@(test)
ast_hover_type_assertion_unary_value_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {
			int,
			f64,
		}

		main :: proc() {
			foo := Foo(0.0)
			i{*}, ok := &foo.(int)
		}
		`,
	}
	test.expect_hover(t, &source, "test.i: ^int")
}

@(test)
ast_hover_type_assertion_unary_value_ok :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {
			int,
			f64,
		}

		main :: proc() {
			foo := Foo(0.0)
			i, ok{*} := &foo.(int)
		}
		`,
	}
	test.expect_hover(t, &source, "test.ok: bool")
}

@(test)
ast_hover_nested_proc_docs_tabs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			/*
			Docs!
				Docs2
			*/
			f{*}oo :: proc() {}
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc()\n---\nDocs!\n\tDocs2\n")
}

@(test)
ast_hover_nested_proc_docs_spaces :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
            /*
            Docs!
                Docs2
            */
			f{*}oo :: proc() {}
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc()\n---\nDocs!\n    Docs2\n")
}

@(test)
ast_hover_propagate_docs_alias_in_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
		// Docs!
		foo :: proc() {} // Comment!

		bar :: foo
		`})
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			my_package.ba{*}r()
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "my_package.bar :: proc()\n---\nDocs!\n---\nComment!")
}

@(test)
ast_hover_propagate_docs_alias_in_package_override :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
		// Docs!
		foo :: proc() {} // Comment!

		// Overridden
		bar :: foo
		`})
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			my_package.ba{*}r()
		}
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "my_package.bar :: proc()\n---\nOverridden\n---\nComment!")
}

@(test)
ast_hover_deferred_attributes :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() {}

		@(deferred_in = fo{*}o)
		bar :: proc() {}
		`,
	}
	test.expect_hover(t, &source, "test.foo :: proc()")
}

@(test)
ast_hover_const_aliases :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: 3 + 4
		B{*}ar :: Foo
		`,
	}
	test.expect_hover(t, &source, "test.Bar :: Foo")
}

@(test)
ast_hover_const_aliases_from_other_pkg :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
		Foo :: 3 + 4
		`})
	source := test.Source {
		main = `package test
		import "my_package"

		B{*}ar :: my_package.Foo
		`,
		packages = packages[:],
	}
	test.expect_hover(t, &source, "test.Bar :: my_package.Foo")
}

@(test)
ast_hover_directives_config_local :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() {
			b{*}ar := #config(TEST, false)
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: bool")
}

@(test)
ast_hover_directives_load_type_local :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc() {
			b{*}ar := #load("foo", string)
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: string")
}

@(test)
ast_hover_directives_load_hash_local :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc() {
			b{*}ar := #load_hash("a", "b")
		}
		`,
	}
	test.expect_hover(t, &source, "test.bar: int")
}

@(test)
ast_hover_directives_config :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		b{*}ar :: #config(TEST, false)
		`,
	}
	test.expect_hover(t, &source, "test.bar :: #config(TEST, false)")
}

@(test)
ast_hover_directives_load :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		b{*}ar :: #load("foo.txt")
		`,
	}
	test.expect_hover(t, &source, "test.bar :: #load(\"foo.txt\")")
}

@(test)
ast_hover_directives_config_info :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		bar :: #c{*}onfig(TEST, false)
		`,
	}
	test.expect_hover(t, &source, "#config(<identifier>, default)\n\nChecks if an identifier is defined through the command line, or gives a default value instead.\n\nValues can be set with the `-define:NAME=VALUE` command line flag.")
}

@(test)
ast_hover_proc_group_bitset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		Foos :: bit_set[Foo]

		foo_one :: proc(i: int, foos: Foos) {}
		foo_two :: proc(s: string, foos: Foos) {}
		foo :: proc {
			foo_one,
			foo_two,
		}

		main :: proc() {
			foo(1, {.A{*}})
		}
		`,
	}
	test.expect_hover(t, &source, "test.Foo: .A")
}

@(test)
ast_hover_soa_struct_field_indexed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct{}

		Bar :: struct {
			foos: #soa[dynamic]Foo,
		}

		bazz :: proc(bar: ^Bar, index: int) {
			f{*}oo := &bar.foos[index]
		}
		`,
	}
	test.expect_hover(t, &source, "test.foo: #soa^#soa[dynamic]Foo")
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
