package tests

import "core:fmt"
import "core:testing"

import "src:common"

import test "src:testing"

@(test)
ast_goto_bit_set_comp_literal :: proc(t: ^testing.T) {
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
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 11}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_set_index_enumerated_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		TestEnum :: enum {
			valueOne,
			valueTwo,
		}

		EnumIndexedArray :: [TestEnum]u32 {
			.valueOne = 1,
			.valueTwo = 2,
		}

		my_proc :: proc() -> u32 {
			arr :: EnumIndexedArray
			return arr[.valueO{*}ne]
		}
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 11}},
	}

	test.expect_definition_locations(t, &source, {location})
}


@(test)
ast_goto_comp_lit_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }

        main :: proc() {
            point := Point {
                x{*} = 2, y = 5, z = 0,
            }
        }
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 12}, end = {line = 2, character = 13}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_struct_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }

        main :: proc() {
            point := Po{*}int {
                x = 2, y = 5, z = 0,
            }
        }
		`,
	}

	location := common.Location {
		range = {start = {line = 1, character = 8}, end = {line = 1, character = 13}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_comp_lit_field_indexed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }

        main :: proc() {
            point := [2]Point {
                {x{*} = 2, y = 5, z = 0},
                {y = 10, y = 20, z = 10},
            }
        }
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 12}, end = {line = 2, character = 13}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_untyped_comp_lit_in_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Struct :: struct {
				one: int,
				two: int,
			}

			my_function :: proc(my_struct: My_Struct) {

			}

			main :: proc() {
				my_function({on{*}e = 2, two = 3})
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 4}, end = {line = 2, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_field_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Bit_Field :: bit_field uint {
				one: int | 1,
				two: int | 1,
			}

			main :: proc() {
				it: My_B{*}it_Field
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 1, character = 3}, end = {line = 1, character = 15}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_field_field_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Bit_Field :: bit_field uint {
				one: int | 1,
				two: int | 1,
			}

			main :: proc() {
				it: My_Bit_Field
				it.on{*}e
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 4}, end = {line = 2, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_field_field_in_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Struct :: bit_field uint {
				one: int | 1,
				two: int | 2,
			}

			my_function :: proc(my_struct: My_Struct) {

			}

			main :: proc() {
				my_function({on{*}e = 2, two = 3})
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 4}, end = {line = 2, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_shadowed_value_decls :: proc(t: ^testing.T) {
	source0 := test.Source {
		main     = `package test
			main :: proc() {
				foo := 1
				
				{
					fo{*}o := 2
				}
			}
		`,
		packages = {},
	}
	test.expect_definition_locations(t, &source0, {{range = {{line = 5, character = 5}, {line = 5, character = 8}}}})

	source1 := test.Source {
		main     = `package test
			main :: proc() {
				foo := 1
				
				{
					foo := 2
					fo{*}o
				}
			}
		`,
		packages = {},
	}
	test.expect_definition_locations(t, &source1, {{range = {{line = 5, character = 5}, {line = 5, character = 8}}}})

	source3 := test.Source {
		main     = `package test
			main :: proc() {
				foo := 1
				
				{
					foo := fo{*}o
				}
			}
		`,
		packages = {},
	}
	test.expect_definition_locations(t, &source3, {{range = {{line = 2, character = 4}, {line = 2, character = 7}}}})
}

@(test)
ast_goto_implicit_super_enum_infer_from_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
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
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 6}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Enum :: enum {
			One,
			Two,
			Three,
			Four,
		}

		my_function :: proc() {
			my_enum: My_Enum
			my_enum = .Fo{*}ur
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 5, character = 3}, end = {line = 5, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_return :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Enum :: enum {
			One,
			Two,
			Three,
			Four,
		}

		my_function :: proc() -> My_Enum {
			return .Fo{*}ur
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 5, character = 3}, end = {line = 5, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_function :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Enum :: enum {
			One,
			Two,
			Three,
			Four,
		}

		my_fn :: proc(my_enum: My_Enum) {

		}

		my_function :: proc() {
			my_fn(.Fo{*}ur)
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 5, character = 3}, end = {line = 5, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_assignment_within_switch :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		Bar :: enum {
			Bar1,
			Bar2,
		}

		Foo :: enum {
			Foo1,
			Foo2,
		}


		main :: proc() {
			my_foo: Foo
			my_bar: Bar
			switch my_foo {
			case .Foo1:
				my_bar = .B{*}ar2
			case .Foo2:
				my_bar = .Bar1
			}
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_variable_declaration_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			bar: [1]Bar
			b{*}ar[0].foo = 5
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_variable_field_definition_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			bar: [1]Bar
			bar[0].fo{*}o = 5
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 6}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_struct_definition_with_empty_line_at_top_of_file :: proc(t: ^testing.T) {
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

	location := common.Location {
		range = {start = {line = 3, character = 2}, end = {line = 3, character = 5}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_enum_from_map_key :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			m: map[Foo]int
			m[.A{*}] = 2
		}
		`,
	}

	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_struct_field_from_proc :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

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
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_proc_named_param :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		foo :: proc(a: int) {}

		main :: proc() {
			a := "hellope"
			foo(a{*} = 0)
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 14}, end = {line = 2, character = 15}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_param_inside_where_clause :: proc(t: ^testing.T) {
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
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_enum_struct_field_without_name :: proc(t: ^testing.T) {
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
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_soa_field :: proc(t: ^testing.T) {
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
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_nested_using_bit_field_field :: proc(t: ^testing.T) {
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
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_nested_using_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			using _: struct {
				b: u8
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
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_package_declaration :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bar :: struct{}
		`})
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			bar: m{*}y_package.Bar
		}
	`,
		packages = packages[:],
	}
	locations := []common.Location {
		{range = {start = {line = 1, character = 9}, end = {line = 1, character = 21}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_package_declaration_with_alias :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bar :: struct{}
		`})
	source := test.Source {
		main = `package test
		import mp "my_package"

		main :: proc() {
			bar: m{*}p.Bar
		}
	`,
		packages = packages[:],
	}
	locations := []common.Location {
		{range = {start = {line = 1, character = 9}, end = {line = 1, character = 11}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}
