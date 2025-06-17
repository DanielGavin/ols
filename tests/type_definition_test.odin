package tests 

import "core:testing"

import "src:common"

import test "src:testing"

@(test)
ast_type_definition_struct_definition :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Bar :: struct {
			bar: int,
		}

		main :: proc() {
			b{*}ar := Bar{}
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_struct_field_definition :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}
		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{
				ba{*}r = Foo{},
			}
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_struct_field_definition_from_use :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}
			bar.ba{*}r = Foo{}
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_struct_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}

			foo := b{*}ar.bar
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 5, character = 2},
			end = {line = 5, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_struct_field_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}

			foo := bar.b{*}ar
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_struct_field_pointer_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: ^Foo,
		}

		main :: proc() {
			bar := Bar{}

			foo := bar.b{*}ar
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_local_pointer_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: ^Foo,
		}

		main :: proc() {
			bar := &Bar{}

			foo := b{*}ar.bar
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 5, character = 2},
			end = {line = 5, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_struct_variable :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}
			ba{*}r.bar = "Test"
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 5, character = 2},
			end = {line = 5, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_struct_field_definition_from_declaration :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			f{*}oo: Foo,
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_procedure_return_value :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		bar :: proc() -> Foo {
			return Foo{}
		}

		main :: proc() {
			f{*}oo := bar()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_procedure_mulitple_return_first_value :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: int,
		}

		new_foo_bar :: proc() -> (Foo, Bar) {
			return Foo{}, Bar{}
		}

		main :: proc() {
			fo{*}o, bar := new_foo_bar()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_procedure_mulitple_return_second_value :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: int,
		}

		new_foo_bar :: proc() -> (Foo, Bar) {
			return Foo{}, Bar{}
		}

		main :: proc() {
			foo, ba{*}r := new_foo_bar()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 5, character = 2},
			end = {line = 5, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_builtin_type :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test

		main :: proc() {
			f{*}oo := "Hello, World!"
		}
		`,
	}

	test.expect_type_definition_locations(t, &source, {})
}

@(test)
ast_type_definition_struct_field_builtin_type :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		main :: proc() {
			foo := Foo{
				f{*}oo = "Hello, World!"
			}
		}
		`,
	}

	test.expect_type_definition_locations(t, &source, {})
}

@(test)
ast_type_definition_struct_field_definition_from_declaration_builtin_type :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			f{*}oo: string,
		}
		`,
	}

	test.expect_type_definition_locations(t, &source, {})
}

@(test)
ast_type_definition_on_proc_with_multiple_return_goto_first_return :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		foo :: proc() -> (Foo, bool) {
			return Foo{}, true
		}

		main :: proc() {
			my_foo, ok := f{*}oo()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_proc_first_return :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		foo :: proc() -> (Foo, bool) {
			return Foo{}, true
		}

		main :: proc() {
			my_foo, ok := f{*}oo()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_proc_with_no_return :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		foo :: proc() {
		}

		main :: proc() {
			f{*}oo()
		}
		`,
	}

	test.expect_type_definition_locations(t, &source, {})
}

@(test)
ast_type_definition_variable_array_type :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			my_int: int,
		}

		Bar :: struct {
			foo: Foo,
		}

		main :: proc() {
			bars: [2]Bar

			b{*}ars[0].foo = Foo{}
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 5, character = 2},
			end = {line = 5, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_proc_from_definition :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		fo{*}o :: proc() -> (Foo, bool) {
			return Foo{}, true
		}

		main :: proc() {
			my_foo, ok := foo()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_proc_with_slice_return :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		fo{*}o :: proc() -> ([]Foo, bool) {
			return {}, true
		}

		main :: proc() {
			my_foo, ok := foo()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_param_of_proc :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: struct {
			foo: string,
		}

		do_foo :: proc(f: Foo) {
		}

		main :: proc() {
			foo := Foo{}
			do_foo(f{*}oo)
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_enum :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		get_foo :: proc() -> Foo {
			return .Foo1
		}

		main :: proc() {
			f{*}oo := get_foo()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_predeclared_variable :: proc(t: ^testing.T) {
	source := test.Source{
		main = `package test
		Foo :: union {
			i64,
			f64,
		}

		get_foo :: proc() -> Foo {
			return 0
		}

		main :: proc() {
			foo: Foo

			f{*}oo = get_foo()
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_external_package :: proc(t: ^testing.T) {
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

		main :: proc() {
			cool: my_package.My_Struct
			cool{*}
		}
		`,
		packages = packages[:],
	}

	location := common.Location {
		uri = "file://test/my_package/package.odin",
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 11},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_external_package_from_proc :: proc(t: ^testing.T) {
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

		get_my_struct :: proc() -> my_package.My_Struct {
			return my_package.My_Struct{}
		}

		main :: proc() {
			my_struct := ge{*}t_my_struct()
		}
		`,
		packages = packages[:],
	}

	location := common.Location {
		uri = "file://test/my_package/package.odin",
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 11},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_external_package_from_proc_slice_return :: proc(t: ^testing.T) {
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

		get_my_struct :: proc() -> []my_package.My_Struct {
			return {}
		}

		main :: proc() {
			my_struct := ge{*}t_my_struct()
		}
		`,
		packages = packages[:],
	}

	location := common.Location {
		uri = "file://test/my_package/package.odin",
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 11},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_external_package_from_external_proc :: proc(t: ^testing.T) {
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

		get_my_struct :: proc() -> My_Struct {
			return My_Struct{}
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			my_struct := my_package.ge{*}t_my_struct()
		}
		`,
		packages = packages[:],
	}

	location := common.Location {
		uri = "file://test/my_package/package.odin",
		range = {
			start = {line = 1, character = 2},
			end = {line = 1, character = 11},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_array_of_pointers :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foos := []^Foo{}
			l := len(f{*}oos)
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 2, character = 2},
			end = {line = 2, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

@(test)
ast_type_definition_type_cast :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			data: ^int
			foo := cast(^Foo)data

			bar := fo{*}o.bar
		}
		`,
	}

	location := common.Location {
		range = {
			start = {line = 2, character = 2},
			end = {line = 2, character = 5},
		},
	}

	test.expect_type_definition_locations(t, &source, {location})
}

