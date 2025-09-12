package tests

import "core:fmt"
import "core:testing"

import "src:common"

import test "src:testing"

@(test)
reference_enum_value_initialize_rhs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			a := e.Chang{*}e_Me
		}

		e :: enum { Change_Me }
		`,
	}

	test.expect_reference_locations(
		t,
		&source,
		{
			{range = {start = {line = 2, character = 10}, end = {line = 2, character = 19}}},
			{range = {start = {line = 5, character = 14}, end = {line = 5, character = 23}}},
		},
	)
}

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
ast_reference_cast_proc_param_with_param_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

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
ast_reference_variable_in_switch_case :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

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
ast_reference_shouldnt_reference_variable_outside_body :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

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
ast_reference_shouldnt_reference_variable_inside_body :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

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

	locations := []common.Location{{range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}}}}

	test.expect_reference_locations(t, &source, locations[:])
}


@(test)
ast_reference_should_reference_variable_inside_body :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

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

@(test)
ast_reference_struct_within_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			foo1: int,
		}

		main :: proc() {
			InnerFoo :: struct {
				foo: Fo{*}o,
			}
			foo := Foo{}

			ifoo := InnerFoo {foo = foo}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 2}, end = {line = 2, character = 5}}},
		{range = {start = {line = 8, character = 9}, end = {line = 8, character = 12}}},
		{range = {start = {line = 10, character = 10}, end = {line = 10, character = 13}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enum_field_list :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			a = 1,
		}

		main :: proc() {
			foo: Foo
			foo = .a{*}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 8, character = 10}, end = {line = 8, character = 11}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enum_field_list_with_constant :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		one :: 1

		Foo :: enum {
			a = on{*}e,
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 2}, end = {line = 2, character = 5}}},
		{range = {start = {line = 5, character = 7}, end = {line = 5, character = 10}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enum_bitset :: proc(t: ^testing.T) {
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

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 6}}},
		{range = {start = {line = 11, character = 13}, end = {line = 11, character = 16}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_field_from_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Bar :: struct {
			bar: int,
		}

		foo :: proc() -> Bar {
			return Bar{}
		}

		main :: proc() {
			bar := foo().b{*}ar
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 6}}},
		{range = {start = {line = 11, character = 16}, end = {line = 11, character = 19}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_proc_with_immediate_return_field_access :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Bar :: struct {
			bar: int,
		}

		foo :: proc() -> Bar {
			return Bar{}
		}

		main :: proc() {
			bar := f{*}oo().bar
			bar2 := foo().bar
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 6, character = 2}, end = {line = 6, character = 5}}},
		{range = {start = {line = 11, character = 10}, end = {line = 11, character = 13}}},
		{range = {start = {line = 12, character = 11}, end = {line = 12, character = 14}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enumerated_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			foos := [Foo][Foo][Foo][Foo]Foo {
				.A = {
					.B = {
						.A = {
							.A{*} = .B
						}
					}
				}
			}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 9, character = 5}, end = {line = 9, character = 6}}},
		{range = {start = {line = 11, character = 7}, end = {line = 11, character = 8}}},
		{range = {start = {line = 12, character = 8}, end = {line = 12, character = 9}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_field_ptr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			bar: ^Ba{*}r
		}

		Bar :: struct {}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 9}, end = {line = 3, character = 12}}},
		{range = {start = {line = 6, character = 2}, end = {line = 6, character = 5}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_and_enum_variant_same_name :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			Bar,
			Bazz
		}

		Bar :: struct {}

		main :: proc() {
			f: Foo
			f = .Bar
			b := B{*}ar{}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 7, character = 2}, end = {line = 7, character = 5}}},
		{range = {start = {line = 12, character = 8}, end = {line = 12, character = 11}}},
	}
	expect_excluded := []common.Location {
		{range = {start = {line = 11, character = 8}, end = {line = 11, character = 11}}},
	}

	test.expect_reference_locations(t, &source, locations[:], expect_excluded)
}

@(test)
ast_reference_enum_variants_comp_lit_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foo: Foo,
		}

		foo :: proc() -> Bar {
			return Bar {
				foo = .A{*},
			}
		}

		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 13, character = 11}, end = {line = 13, character = 12}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enum_variants_comp_lit_return_implicit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foo: Foo,
		}

		foo :: proc() -> Bar {
			return {
				foo = .A{*},
			}
		}

		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 13, character = 11}, end = {line = 13, character = 12}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enum_indexed_array_return_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		foo :: proc() -> [Foo]int {
			return {
				.A{*} = 2,
				.B = 1,
			}
		}

		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 9, character = 5}, end = {line = 9, character = 6}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enum_conflict_switch_statement :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A{*},
			B,
		}

		Bar :: struct {
			foo: Foo,
		}

		foo :: proc() {
			s := "test"
			switch s {
			case "test2":
			}

			bar := Bar{
				foo = .A
			}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 18, character = 11}, end = {line = 18, character = 12}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_enum_nested_with_switch :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A{*},
			B,
		}

		foo :: proc() -> Foo {
			f := Foo.A
			switch f {
			case .A:
				return .B
			case .B
				return .A
			}
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 8, character = 12}, end = {line = 8, character = 13}}},
		{range = {start = {line = 10, character = 9}, end = {line = 10, character = 10}}},
		{range = {start = {line = 13, character = 12}, end = {line = 13, character = 13}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_field_enumerated_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foos: [F{*}oo]Bazz
		}

		Bazz :: struct {}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 2}, end = {line = 2, character = 5}}},
		{range = {start = {line = 8, character = 10}, end = {line = 8, character = 13}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_field_map_key :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: int

		Bar :: struct {}

		Bazz :: struct {
			bars: map[Fo{*}o]Bar
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 2}, end = {line = 2, character = 5}}},
		{range = {start = {line = 7, character = 13}, end = {line = 7, character = 16}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_field_map_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: int

		Bar :: struct {}

		Bazz :: struct {
			bars: map[Foo]B{*}ar
		}

		`,
	}

	locations := []common.Location {
		{range = {start = {line = 4, character = 2}, end = {line = 4, character = 5}}},
		{range = {start = {line = 7, character = 17}, end = {line = 7, character = 20}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_named_parameter_same_as_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		foo :: proc(a: int) {}

		main :: proc() {
			a := "hellope"
			foo(a{*} = 0)
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 14}, end = {line = 2, character = 15}}},
		{range = {start = {line = 6, character = 7}, end = {line = 6, character = 8}}},
	}
	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_comp_lit_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foo: Foo,
		}

		foo :: proc() -> Bar {
			return Bar {
				fo{*}o = .A,
			}
		}

		`,
	}

	locations := []common.Location {
		{range = {start = {line = 8, character = 3}, end = {line = 8, character = 6}}},
		{range = {start = {line = 13, character = 4}, end = {line = 13, character = 7}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_inside_where_clause :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(x: [2]int)
			where len(x) > 1,
				  type_of(x{*}) == [2]int {
		}
	`,
	}

	locations := []common.Location {
		{range = {start = {line = 1, character = 14}, end = {line = 1, character = 15}}},
		{range = {start = {line = 2, character = 13}, end = {line = 2, character = 14}}},
		{range = {start = {line = 3, character = 14}, end = {line = 3, character = 15}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_union_switch_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: union {
			int,
			string
		}

		main :: proc() {
			foo: Foo
			#partial switch v{*} in foo {
			case int:
				bar := v + 1
			case string:
				bar := "test" + v
			}
		}
	`,
	}

	locations := []common.Location {
		{range = {start = {line = 8, character = 19}, end = {line = 8, character = 20}}},
		{range = {start = {line = 10, character = 11}, end = {line = 10, character = 12}}},
		{range = {start = {line = 12, character = 20}, end = {line = 12, character = 21}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_enum_struct_field_without_name :: proc(t: ^testing.T) {
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
			bar: Bar = {.A{*}}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 2, character = 3}, end = {line = 2, character = 4}}},
		{range = {start = {line = 11, character = 16}, end = {line = 11, character = 17}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_poly_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(array: $A/[dynamic]^$T) {
			for e{*}lem, i in array {
				elem
			}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 2, character = 7}, end = {line = 2, character = 11}}},
		{range = {start = {line = 3, character = 4}, end = {line = 3, character = 8}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_soa_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			foos: #soa[]Foo
			x := foos.x{*}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 2, character = 3}, end = {line = 2, character = 4}}},
		{range = {start = {line = 7, character = 13}, end = {line = 7, character = 14}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_soa_pointer_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			foos: #soa^#soa[]Foo
			x := foos.x{*}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 2, character = 3}, end = {line = 2, character = 4}}},
		{range = {start = {line = 7, character = 13}, end = {line = 7, character = 14}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_nested_switch_cases :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B{*},
		}

		Bar :: enum {
			C,
			D,
		}

		main :: proc() {
			foo: Foo
			bar: Bar

			switch foo {
			case .A:
				#partial switch bar {
				case .D:
				}
			case .B:
			}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 20, character = 9}, end = {line = 20, character = 10}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_switch_cases_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B{*},
		}

		Bar :: enum {
			C,
			D,
		}

		main :: proc() {
			foo: Foo
			bar: Bar

			switch foo {
			case .A:
				if bar == .C {}
			case .B:
			}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}}},
		{range = {start = {line = 18, character = 9}, end = {line = 18, character = 10}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_field_matrix_row :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: int

		Bar :: struct {}

		Bazz :: struct {
			bars: matrix[Fo{*}o, 2]Bar
		}

		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 2}, end = {line = 2, character = 5}}},
		{range = {start = {line = 7, character = 16}, end = {line = 7, character = 19}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_reference_struct_field_bitfield_backing_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: int

		Bar :: struct {}

		Bazz :: struct {
			bars: bit_field Fo{*}o {
			}
		}

		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 2}, end = {line = 2, character = 5}}},
		{range = {start = {line = 7, character = 19}, end = {line = 7, character = 22}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_comp_lit_map_key :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		Foo :: struct {
			a{*}: int,
		}

		Bar :: struct {
			b: int,
		}

		main :: proc() {
			m: map[Foo]Bar
			m[{a = 1}] = {b = 2}
		}
		`,
	}
	locations := []common.Location {
		{range = {start = {line = 2, character = 3}, end = {line = 2, character = 4}}},
		{range = {start = {line = 11, character = 6}, end = {line = 11, character = 7}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_comp_lit_map_value :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		Foo :: struct {
			a: int,
		}

		Bar :: struct {
			b{*}: int,
		}

		main :: proc() {
			m: map[Foo]Bar
			m[{a = 1}] = {b = 2}
		}
		`,
	}
	locations := []common.Location {
		{range = {start = {line = 6, character = 3}, end = {line = 6, character = 4}}},
		{range = {start = {line = 11, character = 17}, end = {line = 11, character = 18}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_nested_using_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			using _: struct {
				b: u8,
			}
		}

		main :: proc() {
			foo: Foo
			b := foo.b{*}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 4, character = 4}, end = {line = 4, character = 5}}},
		{range = {start = {line = 10, character = 12}, end = {line = 10, character = 13}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_nested_using_bit_field_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			using _: bit_field u8 {
				b: u8 | 4
			}
		}

		main :: proc() {
			foo: Foo
			b := foo.b{*}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 4, character = 4}, end = {line = 4, character = 5}}},
		{range = {start = {line = 10, character = 12}, end = {line = 10, character = 13}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}

@(test)
ast_references_nested_using_bit_field_field_from_declaration :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			using _: bit_field u8 {
				b{*}: u8 | 4
			}
		}

		main :: proc() {
			foo: Foo
			b := foo.b
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 4, character = 4}, end = {line = 4, character = 5}}},
		{range = {start = {line = 10, character = 12}, end = {line = 10, character = 13}}},
	}

	test.expect_reference_locations(t, &source, locations[:])
}
