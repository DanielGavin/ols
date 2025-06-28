package tests

import "core:fmt"
import "core:testing"

import "src:common"

import test "src:testing"


@(test)
reference_enum_type_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		TestEnum :: enum {
			valueOne, 
			valueTwo,
		}

		EnumIndexedArray :: [TestEnum]u32 {
			.value{*}One = 1,
			.valueTwo = 2,
		}

		my_proc :: proc() -> u32 {
			arr :: EnumIndexedArray
			return arr[.valueOne]
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 2, character = 3}, end = {line = 2, character = 11}}},
			{range = {start = {line = 7, character = 4}, end = {line = 7, character = 12}}},
			{range = {start = {line = 13, character = 15}, end = {line = 13, character = 23}}},
		},
	)
}

@(test)
reference_variables_in_function :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		my_function :: proc() {
			a := 2
			b := a
			c := 2 + b{*}
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
			{range = {start = {line = 4, character = 12}, end = {line = 4, character = 13}}},
		},
	)
}

@(test)
reference_variables_in_function_with_empty_line_at_top_of_file :: proc(t: ^testing.T) {
	source := test.Source {
		main = `
		package test
		my_function :: proc() {
			a := 2
			b := a
			c := 2 + b{*}
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 4, character = 3}, end = {line = 4, character = 4}}},
			{range = {start = {line = 5, character = 12}, end = {line = 5, character = 13}}},
		},
	)
}

@(test)
reference_variables_in_function_parameters :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		my_function :: proc(a: int) {
			b := a{*}
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{{range = {start = {line = 1, character = 22}, end = {line = 1, character = 23}}}},
	)
}

@(test)
reference_selectors_in_function :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		My_Struct :: struct {
			a: int,
		}

		my_function :: proc() {
			my: My_Struct
			my.a{*} = 2
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 2, character = 3}, end = {line = 2, character = 4}}},
			{range = {start = {line = 7, character = 6}, end = {line = 7, character = 7}}},
		},
	)
}


@(test)
reference_field_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			soo_many_cases: int,
		}

		My_Struct :: struct {
			foo: Foo,
		}

		my_function :: proc(my_struct: My_Struct) {
			my := My_Struct {
				foo = {soo_many_cases{*} = 2},
			}
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 2, character = 3}, end = {line = 2, character = 17}}},
			{range = {start = {line = 11, character = 11}, end = {line = 11, character = 25}}},
		},
	)
}

@(test)
reference_field_comp_lit_infer_from_function :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			soo_many_cases: int,
		}

		My_Struct :: struct {
			foo: Foo,
		}

		my_function :: proc(my_struct: My_Struct) {
			my_function({foo = {soo_many_cases{*} = 2}})
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 2, character = 3}, end = {line = 2, character = 17}}},
			{range = {start = {line = 10, character = 23}, end = {line = 10, character = 37}}},
		},
	)
}

@(test)
reference_field_comp_lit_infer_from_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			soo_many_cases: int,
		}

		My_Struct :: struct {
			foo: Foo,
		}

		my_function :: proc() -> My_Struct {
			return {foo = {soo_many_cases{*} = 2}}
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 2, character = 3}, end = {line = 2, character = 17}}},
			{range = {start = {line = 10, character = 18}, end = {line = 10, character = 32}}},
		},
	)
}


@(test)
reference_enum_field_infer_from_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Sub_Enum1 :: enum {
			ONE,
		}
		Sub_Enum2 :: enum {
			TWO,
		}

		Super_Enum :: union {
			Sub_Enum1,
			Sub_Enum2,
		}

		main :: proc() {
			my_enum: Super_Enum
			my_enum = .ON{*}E
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 2, character = 3}, end = {line = 2, character = 6}}},
			{range = {start = {line = 15, character = 14}, end = {line = 15, character = 17}}},
		},
	)
}


@(test)
reference_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Mouse :: struct {
			x, y: f32,
		}

		mouse: Mouse

		random_procedure :: proc(x, y: f32) {
			mouse.x += x{*}
			mouse.y += y
		}
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 8, character = 14}, end = {line = 8, character = 15}}},
			{range = {start = {line = 7, character = 27}, end = {line = 7, character = 28}}},
		},
	)
}

@(test)
ast_reference_variable_declaration_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			bar: [2]Bar
			bar[0].foo = 5
			b{*}ar[1].foo = 6
		}
		`,
		packages = {},
	}

	locations := []common.Location {
		{range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}}},
		{range = {start = {line = 8, character = 3}, end = {line = 8, character = 6}}},
		{range = {start = {line = 9, character = 3}, end = {line = 9, character = 6}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_variable_uses_from_declaration :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			b{*}ar: Bar
			bar.foo = 5
			bar.foo = 6
		}
		`,
		packages = {},
	}

	locations := []common.Location {
		{range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}}},
		{range = {start = {line = 8, character = 3}, end = {line = 8, character = 6}}},
		{range = {start = {line = 9, character = 3}, end = {line = 9, character = 6}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_variable_uses_from_declaration_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			b{*}ar: [2]Bar
			bar[0].foo = 5
			bar[1].foo = 6
		}
		`,
		packages = {},
	}

	locations := []common.Location {
		{range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}}},
		{range = {start = {line = 8, character = 3}, end = {line = 8, character = 6}}},
		{range = {start = {line = 9, character = 3}, end = {line = 9, character = 6}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_variable_declaration_field_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			bar: [2]Bar
			bar[0].foo = 5
			bar[1].f{*}oo = 6
		}
		`,
		packages = {},
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 6}}},
		{range = {start = {line = 8, character = 10}, end = {line = 8, character = 13}}},
		{range = {start = {line = 9, character = 10}, end = {line = 9, character = 13}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_cast_proc_param_with_param_expr :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct{
			data: int,
			len: int,
		}

		Bar :: struct{
			data: int,
			len: int,
		}

		foo :: proc(bu{*}f: ^Foo, n: int) {
			(cast(^Bar)&buf.data).len -= n
			buf.r_offset = (buf.r_offset + n) % cap(buf.data)
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 12, character = 14}, end = {line = 12, character = 17}}},
		{range = {start = {line = 13, character = 15}, end = {line = 13, character = 18}}},
		{range = {start = {line = 14, character = 19}, end = {line = 14, character = 22}}},
		{range = {start = {line = 14, character = 43}, end = {line = 14, character = 46}}},
		{range = {start = {line = 14, character = 3}, end = {line = 14, character = 6}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_variable_in_switch_case :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: enum {
			Bar1,
			Bar2,
		}

		Foo :: struct {
			foo1: int,
		}

		main :: proc() {
			bar: Bar

			#partial switch bar {
			case .Bar1:
				foo := Foo{}
				f{*}oo.foo1 = 2
			}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 17, character = 4}, end = {line = 17, character = 7}}},
		{range = {start = {line = 17, character = 4}, end = {line = 17, character = 7}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_shouldnt_reference_variable_outside_body :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			foo1: int,
		}

		main :: proc() {
			foo: Foo
			{
				fo{*}o := Foo{}
				foo.foo1 = 2
			}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 9, character = 4}, end = {line = 9, character = 7}}},
		{range = {start = {line = 10, character = 4}, end = {line = 10, character = 7}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_shouldnt_reference_variable_inside_body :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			foo1: int,
		}

		main :: proc() {
			fo{*}o: Foo
			{
				foo := Foo{}
				foo.foo1 = 2
			}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}


@(test)
ast_reference_should_reference_variable_inside_body :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			foo1: int,
		}

		main :: proc() {
			fo{*}o: Foo
			{
				foo.foo1 = 2
			}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}}},
		{range = {start = {line = 9, character = 4}, end = {line = 9, character = 7}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}
