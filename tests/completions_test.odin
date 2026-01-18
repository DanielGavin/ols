package tests

import "core:strings"
import "core:testing"

import test "src:testing"

@(test)
ast_simple_struct_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int, // test comment
			three: int,
		}

		main :: proc() {
			my_struct: My_Struct;
			my_struct.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(
		t,
		&source,
		".",
		{"My_Struct.one: int", "My_Struct.two: int\n---\ntest comment", "My_Struct.three: int"},
	)
}

@(test)
ast_index_array_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: [] My_Struct;
			my_struct[2].{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"})
}

@(test)
ast_index_dynamic_array_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: [dynamic] My_Struct;
			my_struct[2].{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"})
}

@(test)
ast_struct_pointer_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: ^My_Struct;
			my_struct.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"})
}

@(test)
ast_struct_take_address_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: My_Struct;
			my_pointer := &my_struct;
			my_pointer.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"})
}

@(test)
ast_struct_deref_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: ^^My_Struct;
			my_deref := my_struct^;
			my_deref.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"})
}

@(test)
ast_range_map :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_map: map[int]My_Struct;
			
			for key, value in my_map {
				value.{*}
			}

		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"})
}

@(test)
ast_range_array :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_array: []My_Struct;
			
			for value in my_array {
				value.{*}
			}

		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"})
}

@(test)
ast_completion_identifier_proc_group :: proc(t: ^testing.T) {

	source := test.Source {
		main     = `package test

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
			grou{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.group_function :: proc (..)"})
}

@(test)
ast_completion_identifier_proc_group_2 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		raw_data_slice :: proc(v: $T/[]$E) -> [^]E {
		}

		zzcool :: proc {
			raw_data_slice,
		}

		main :: proc() {
			zzco{*}
		}

		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.zzcool :: proc(v: $T/[]$E) -> [^]E"})
}

@(test)
ast_completion_untyped_proc_group :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		add_num :: proc(a, b: int) -> int {return a + b}
		add_vec :: proc(a, b: [2]f32) -> [2]f32 {return a + b}

		add :: proc {
			add_num,
			add_vec,
		}

		main :: proc() {
			foozz := add(2, 10)
			fooz{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.foozz: int"})
}


@(test)
ast_completion_in_comp_lit_type :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_comp := My_{*} {
			};
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.My_Struct :: struct {..}"})
}

@(test)
ast_completion_range_struct_selector_strings :: proc(t: ^testing.T) {

	source := test.Source {
		main     = `package test

		My_Struct :: struct {
			array: []string,
		}

		main :: proc() {
			my_struct: My_Struct;
	
			for value in my_struct.array {
				val{*}
			}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.value: string"})
}

@(test)
ast_completion_selector_on_indexed_array :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Foo :: struct {
			a: int,
			b: int,
		}

		My_Struct :: struct {
			array: []My_Foo,
		}

		main :: proc() {
			my_struct: My_Struct;
	
			my_struct.array[len(my_struct.array)-1].{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Foo.a: int", "My_Foo.b: int"})
}

@(test)
index_package_completion :: proc(t: ^testing.T) {

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
            my_package.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"my_package.My_Struct :: struct {..}"})
}

@(test)
ast_generic_make_slice :: proc(t: ^testing.T) {

	source := test.Source {
		main     = `package test
		Allocator :: struct {

		}
		Context :: struct {
			allocator: Allocator,
		}
		make_slice :: proc($T: typeid/[]$E, #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}

		My_Struct :: struct {
			my_int: int,
		}

		main :: proc() {
			my_slice := make_slice([]My_Struct, 23);
			my_slic{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.my_slice: []My_Struct"})
}

@(test)
ast_named_procedure_1 :: proc(t: ^testing.T) {

	source := test.Source {
		main     = `package test
		proc_a :: proc(a: int, b: int) -> int {
		}

		proc_b :: proc(a: int, b: bool) -> bool {
		}

		my_group :: proc {proc_a, proc_b};

		main :: proc() {
			my_bool := my_group(b = false, a = 2);
			my_boo{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.my_bool: bool"})
}

@(test)
ast_named_procedure_2 :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		proc_a :: proc(a: int, b: int) -> int {
		}

		proc_b :: proc(a: int, b: bool) -> bool {
		}

		my_group :: proc {proc_a, proc_b};

		main :: proc() {
			my_bool := my_group(b = false);
			my_boo{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.my_bool: bool"})
}

@(test)
ast_swizzle_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		main :: proc() {
			my_array: [4] f32;
			my_array.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(
		t,
		&source,
		".",
		{"x: f32", "y: f32", "z: f32", "w: f32", "r: f32", "g: f32", "b: f32", "a: f32"},
	)
}

@(test)
ast_swizzle_completion_one_component :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		main :: proc() {
			my_array: [4] f32;
			my_array.x{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"xx: [2]f32", "xy: [2]f32", "xz: [2]f32", "xw: [2]f32"})
}

@(test)
ast_swizzle_completion_few_components :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		main :: proc() {
			my_array: [2] f32;
			my_array.x{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"xx: [2]f32", "xy: [2]f32"})
}


@(test)
ast_swizzle_resolve_one_components :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		main :: proc() {
			my_array: [4]f32;
			my_swizzle := my_array.x;
			my_swizz{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.my_swizzle: f32"})
}

@(test)
ast_swizzle_resolve_two_components :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		main :: proc() {
			my_array: [4]f32;
			my_swizzle := my_array.xx;
			my_swizz{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.my_swizzle: [2]f32"})
}

@(test)
ast_swizzle_resolve_one_component_struct_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		My_Struct :: struct {
			one: int,
			two: int,
		};
		main :: proc() {
			my_array: [4] My_Struct;
			my_array.x.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int"})
}

@(test)
ast_for_in_for_from_different_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
				My_Bar :: struct {
					number: int,
				}
				
				My_Foo :: struct {
					elems: []^My_Bar,
				}			
		`,
		},
	)

	source := test.Source {
		main     = `package test	
		import "my_package"		
		main :: proc() {
			my_foos: []^my_package.My_Foo
			for foo in my_foos {
				for my_bar in foo.elems {
					my_bar.{*}
				}
			}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, "", {"My_Bar.number: int"})
}

@(test)
ast_for_in_identifier_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Struct :: struct {
			one: int,
			two: int,
		};
		
		main :: proc() {
		
			my_array: [4]My_Struct;
		
		
			for my_element in my_array {
				my_elem{*}
			}
		
		}
		`,
		packages = {},
	}


	test.expect_completion_docs(t, &source, "", {"test.my_element: test.My_Struct"})
}

@(test)
ast_for_in_call_expr_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		Step :: struct {
			data: int,
		}

		main :: proc() {
			list :: proc() -> []Step {
				return nil
			}
			for zstep in list() {
				zst{*}
			}
		}
		`,
		packages = {},
	}


	test.expect_completion_docs(t, &source, ".", {"test.zstep: test.Step"})
}


@(test)
ast_completion_poly_struct_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		RenderPass :: struct(type : typeid) { list : ^int, data : type, }

		LightingAccumPass2 :: struct {
			foo: int,
		}		
		
		execute_lighting_pass2 :: proc(pass : RenderPass(LightingAccumPass2)) {
			pass.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"RenderPass.list: ^int"})
}

@(test)
ast_generic_make_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		make :: proc{
			make_dynamic_array_len,
		};
		make_slice :: proc($T: typeid/[]$E, #any_int len: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}
		make_map :: proc($T: typeid/map[$K]$E, #any_int cap: int = DEFAULT_RESERVE_CAPACITY, loc := #caller_location) -> T {
		}
		make_dynamic_array :: proc($T: typeid/[dynamic]$E, loc := #caller_location) -> (T, Allocator_Error) #optional_second {		
		}
		make_dynamic_array_len :: proc($T: typeid/[dynamic]$E, #any_int len: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}
		make_dynamic_array_len_cap :: proc($T: typeid/[dynamic]$E, #any_int len: int, #any_int cap: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}

		My_Struct :: struct {
			my_int: int,
		}

		main :: proc() {
			allocator: Allocator;
			my_array := make([dynamic]My_Struct, 343);
			my_array[2].{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.my_int: int"})
}

@(test)
ast_generic_make_completion_2 :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		make :: proc{
			make_dynamic_array,
			make_dynamic_array_len,
			make_dynamic_array_len_cap,
			make_map,
			make_slice,
		};
		make_slice :: proc($T: typeid/[]$E, #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (T, Allocator_Error) #optional_allocator_error {
		}
		make_map :: proc($T: typeid/map[$K]$E, #any_int cap: int = DEFAULT_RESERVE_CAPACITY, loc := #caller_location) -> T {
		}
		make_dynamic_array :: proc($T: typeid/[dynamic]$E, loc := #caller_location) -> (T, Allocator_Error) #optional_second {		
		}
		make_dynamic_array_len :: proc($T: typeid/[dynamic]$E, #any_int len: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}
		make_dynamic_array_len_cap :: proc($T: typeid/[dynamic]$E, #any_int len: int, #any_int cap: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}

		My_Struct :: struct {
			my_int: int,
		}

		main :: proc() {
			my_array := make([]My_Struct, 343);
			my_array[2].{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.my_int: int"})
}


@(test)
ast_generic_make_completion_3 :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
				make :: proc{
					make_dynamic_array,
					make_dynamic_array_len,
					make_dynamic_array_len_cap,
					make_map,
					make_slice,
				};
				make_slice :: proc($T: typeid/[]$E, #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (T, Allocator_Error) #optional_allocator_error {
				}
				make_map :: proc($T: typeid/map[$K]$E, #any_int cap: int = DEFAULT_RESERVE_CAPACITY, loc := #caller_location) -> T {
				}
				make_dynamic_array :: proc($T: typeid/[dynamic]$E, loc := #caller_location) -> (T, Allocator_Error) #optional_second {		
				}
				make_dynamic_array_len :: proc($T: typeid/[dynamic]$E, #any_int len: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
				}
				make_dynamic_array_len_cap :: proc($T: typeid/[dynamic]$E, #any_int len: int, #any_int cap: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
				}	
		`,
		},
	)

	source := test.Source {
		main     = `package test
		import "my_package"
		
		My_Struct :: struct {
			my_int: int,
		}

		main :: proc() {
			my_array := my_package.make([]My_Struct, 343);
			my_ar{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"test.my_array: []My_Struct"})
}

@(test)
ast_struct_for_in_switch_stmt_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		PlatformContext :: struct {
			windows:  [dynamic]Window,
			running:  bool,
		}
		
		platform_context: PlatformContext;
		
		Window :: struct {
			width:      int,
			height:     int,
		}

		main :: proc() {
			switch (message) {
			case win32.WM_SIZE:
				for w in platform_context.windows {
					w.{*}
				}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"Window.height: int"})
}


@(test)
ast_overload_with_any_int_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_group :: proc{
			with_any_int,
			with_bool,
		};
		with_any_int :: proc(#any_int a: int) -> bool {
		}
		with_bool :: proc(a: bool) -> int {
		}

		main :: proc() {
			my_uint: uint = 0;
			my_value := my_group(my_uint);
			my_val{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.my_value: bool"})
}

@(test)
ast_overload_with_any_int_with_poly_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		my_group :: proc{
			with_any_int,
			with_bool,
		};
		with_any_int :: proc($T: typeid/[dynamic]$E, #any_int a: int) -> bool {
		}
		with_bool :: proc($T: typeid/[dynamic]$E, a: bool) -> int {
		}

		main :: proc() {
			my_uint: uint = 0;
			my_value := my_group([dynamic]f32, my_uint);
			my_val{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.my_value: bool"})
}


/*
	Wait for odin issue to be done 
@(test)
ast_completion_in_between_struct :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		Format_Decision_State :: struct {
			type: Format_Decision_Type,
			current_token: ^Format_Token,
			previous_token: ^Format_Token,
			line: ^Unwrapped_Line,
			a{*}
			indent: int,
			width: int,
			penalty: f32,
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.my_value: bool"});
}

*/

@(test)
ast_overload_with_any_int_index_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		my_group :: proc{
			with_any_int,
			with_bool,
		};
		with_any_int :: proc($T: typeid/[dynamic]$E, #any_int a: int) -> bool {
		}
		with_bool :: proc($T: typeid/[dynamic]$E, a: bool) -> int {
		}
		`,
		},
	)

	source := test.Source {
		main     = `package test

		import "my_package"

		main :: proc() {
			my_uint: uint = 0;
			my_value := my_package.my_group([dynamic]f32, my_uint);
			my_val{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"test.my_value: bool"})
}


@(test)
ast_package_procedure_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "my_package", source = `package my_package
		my_proc :: proc() -> bool {
		}
		`},
	)

	source := test.Source {
		main     = `package test

		import "my_package"

		main :: proc() {
			my_package.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"my_package.my_proc :: proc() -> bool"})
}

@(test)
ast_poly_with_comp_lit_empty_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
	
		My_Struct :: struct {
			a: int,
		}

		new_type :: proc($T: typeid, pos, end: My_Struct) -> ^T {
		}

		main :: proc() {
			t := new_type(My_Struct, {}, {})
			t.{*}
		}
		`,
		packages = {},
	}

	//FIXME
	//test.expect_completion_details(t, &source, ".", {"my_package.my_proc: proc() -> bool"});
}

@(test)
ast_global_struct_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package main

		Foo :: struct { x: int }
		foo := Foo{}
		main :: proc() {
			x := foo.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"Foo.x: int"})
}

@(test)
ast_global_non_mutable_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package main

		Foo :: struct { x: int }
		main :: proc() {
			x := Foo.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {})
}

@(test)
ast_basic_value_untyped_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package main

		main :: proc() {
			xaa := 2
			xa{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.xaa: int"})
}

@(test)
ast_basic_value_binary_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package main

		main :: proc() {
			xaa := 2
			xb2 := xaa - 2
			xb{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.xb2: int"})
}

@(test)
ast_file_private_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package

		@(private="file") my_proc :: proc() -> bool {
		}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		main :: proc() {
			my_package.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {})
}

@(test)
ast_file_tag_private_completion :: proc(t: ^testing.T) {
	comments := []string{"// +private", "//+private file", "// +build  ignore"}

	for comment in comments {

		b := strings.builder_make(context.temp_allocator)

		strings.write_string(&b, comment)
		strings.write_string(&b, `
			package my_package

			my_proc :: proc() -> bool {}
		`)

		source := test.Source {
			main     = `package main
			import "my_package"
			main :: proc() {
				my_package.{*}
			}
			`,
			packages = {{pkg = "my_package", source = strings.to_string(b)}},
		}

		test.expect_completion_docs(t, &source, ".", {})
	}
}

@(test)
ast_non_mutable_variable_struct_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct { a: int }
		Im :: My_Struct;
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		main :: proc() {
			my_package.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"my_package.Im :: struct {..}"})
}

@(test)
ast_mutable_variable_struct_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct { a: int }
		var: My_Struct;
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		main :: proc() {
			my_package.var.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.a: int"})
}

@(test)
ast_out_of_block_scope_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			{
				zzaabb := 2
			}
			zzaab{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {})
}

@(test)
ast_value_decl_multiple_name_same_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			xaaaa, yaaaa: string
			xaaaa = "hi"
			yaaa{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.yaaaa: string"})
}

@(test)
ast_value_decl_multi_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			x: []int
			y: []int
			xzz, yzz := x[0], y[0]

			yz{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.yzz: int"})
}


@(test)
ast_value_decl_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Struct :: struct {
			a: int,
		}
		main :: proc() {
			my_struct := My_Struct {
				a = 2,
			}

			my_struct.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.a: int"})
}

@(test)
ast_value_decl_comp_lit_infer_with_maybe :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Maybe :: union($T: typeid) {T}

		Inner :: struct {
			a, b, c: int,
		}
		Outer :: struct {
			inner: Maybe(Inner),
		}


		main :: proc() {
			outer := Outer {
				inner = Inner{ {*}},
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Inner.a: int", "Inner.b: int", "Inner.c: int"})
}


@(test)
ast_multi_pointer_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			faa: [^]int
			fa{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.faa: [^]int"})
}

@(test)
ast_multi_pointer_indexed_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			faa: [^]int
			sap := faa[1]
			sa{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.sap: int"})
}

@(test)
ast_implicit_named_comp_lit_bitset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Enum :: enum {A, B, C}
		My_Bitset :: bit_set[My_Enum]
		My_Struct :: struct {
			bits: My_Bitset,
		}

		main :: proc() {
			inst := My_Struct {
				bits = {.{*}}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"A", "B", "C"})
}

@(test)
ast_implicit_unnamed_comp_lit_bitset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Enum :: enum {A, B, C}
		My_Bitset :: bit_set[My_Enum]
		My_Struct :: struct {
			bits: My_Bitset,
			bits_2: My_Bitset,
		}

		main :: proc() {
			inst := My_Struct {
				{.A}, {.{*}},
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"A", "B", "C"})
}

@(test)
ast_implicit_unnamed_comp_lit_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Enum :: enum {A, B, C}

		My_Struct :: struct {
			enums: My_Enum,
			enums_2: My_Enum,
		}

		main :: proc() {
			inst := My_Struct {
				.A, .{*}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"A", "B", "C"})
}

@(test)
ast_implicit_mixed_named_and_unnamed_comp_lit_bitset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Enum :: enum {A, B, C}
		My_Bitset :: bit_set[My_Enum]
		My_Struct_2 :: struct {
			bitset_1: My_Bitset,
			bitset_2: My_Bitset,
		}
		My_Struct :: struct {
			foo: My_Struct_2,
		}

		main :: proc() {
			inst := My_Struct {
				foo = {{.A}, {.{*}}, {.B} }
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"A", "B", "C"})
}

@(test)
ast_comp_lit_in_complit_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Struct_2 :: struct {
			aaa: int,
			aab: int,
		}
		My_Struct :: struct {
			foo: My_Struct_2,
		}

		main :: proc() {
			inst := My_Struct {
				foo = {
					a{*}
				}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"My_Struct_2.aab: int", "My_Struct_2.aaa: int"})
}

@(test)
ast_inlined_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Struct :: struct {
			foo: struct {
				a: int,
				b: int,
			},
		}

		main :: proc() {
			inst: My_Struct
			inst.foo.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"struct.a: int", "struct.b: int"})
}

@(test)
ast_inlined_union :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		My_Struct :: struct {
			variant: union {int, f32},
		}

		main :: proc() {
			inst: My_Struct
			inst.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.variant: union {..}"})
}

@(test)
ast_union_identifier_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Union :: union {
			int,
		}

		main :: proc() {
			a: My_{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"test.My_Union :: union {..}"})
}

@(test)
ast_union_poly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Union :: union($T: typeid) {T}

		main :: proc() {
			m: My_Union(int)
    		m.{*}
		}
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"(int)"})
}

@(test)
ast_maybe_first_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Maybe :: union($T: typeid) {T}

		main :: proc() {
			m: Maybe(int)
    		v, ok := m.?
			v{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.v: int"})
}

@(test)
ast_maybe_second_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			m: Maybe(int)
    		v, ok := m.?
			ok{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.ok: bool"})
}

@(test)
ast_maybe_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		My_Union :: union($T: typeid) {T}

		main :: proc() {
			m: My_Union([5]u8)
    		m.{*}
		}
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"([5]u8)"})
}


@(test)
ast_maybe_index_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "my_package", source = `package my_package
		Maybe :: union($T: typeid) {T}
		`},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		main :: proc() {
			m: my_package.Maybe(int)
    		m.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_labels(t, &source, ".", {"(int)"})
}

@(test)
ast_distinct_u32_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		f :: proc() {
			Distinct_Type :: distinct u32

			d: Distinct_Type
			d{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.d: test.Distinct_Type"})
}

@(test)
ast_new_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		new :: proc($T: typeid) -> (^T, Allocator_Error) #optional_second {
		}

		main :: proc() {
			adzz := new(int);
			adzz{*}
		}

		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.adzz: ^int"})
}

@(test)
ast_new_completion_for_proc_defined :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		new :: proc($T: typeid) -> (^T, Allocator_Error) #optional_second {
		}

		main :: proc() {
			Http_Ctx :: struct {
				user_ctx: rawptr,
			}
			http_ctx := new(Http_Ctx)
			http_c{*}
		}

		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.Http_Ctx :: struct {..}"})
}

@(test)
ast_new_clone_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		new_clone :: proc(data: $T) -> (^T, Allocator_Error) #optional_second {
		}

		Foo :: struct {}

		main :: proc() {
			adzz := new_clone(Foo{});
			adzz{*}
		}

		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.adzz: ^test.Foo"})
}

@(test)
ast_rawtr_cast_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		
		main :: proc() {
			raw: rawptr
			my_int := cast(int)raw;
			my_i{*}
		}

		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.my_int: int"})
}

ast_overload_with_procedure_return :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		import "my_package"	
	

		my_group :: proc {
			make_slice,
			make_map,
		}

		make_slice :: proc($T: typeid/[]$E, #any_int len: int) -> (T, Allocator_Error) #optional_second {}
		make_map :: proc(a: int) -> int {}


		test_int :: proc() -> int {}
		main :: proc() {
			my_in := my_group([]int, test_int())
			my_in{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.my_in: []int"})
}


@(test)
ast_index_proc_parameter_completion :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct {
			a: int,
			b: int,
		}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		f :: proc(param: my_package.My_Struct) {
			para{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"test.param: my_package.My_Struct"})
}

@(test)
ast_implicit_completion_in_enum_array_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			foo :: enum{ one, two }
			bar := [foo]int{
			  .one = 1,
			  .{*}two = 2, 
			}
	    }
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"two"})
}

@(test)
ast_implicit_enum_value_decl_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Foo :: enum { Aa, Ab, Ac, Ad }
		main :: proc() {
			foo: Foo = .{*}
	    }
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"Aa", "Ab", "Ac", "Ad"})
}

@(test)
ast_implicit_bitset_value_decl :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Foo :: enum { Aa, Ab, Ac, Ad }
		Foo_Set :: bit_set[Foo]
		main :: proc() {
			foo_set := Foo_Set { .{*} }
	    }
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"Aa", "Ab", "Ac", "Ad"})
}

@(test)
ast_implicit_bitset_add :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Foo :: enum { Aa, Ab, Ac, Ad }
		Foo_Set :: bit_set[Foo]
		main :: proc() {
			foo_set: Foo_Set
			foo_set += .{*}
	    }
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"Aa", "Ab", "Ac", "Ad"})
}

@(test)
ast_enum_complete :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Foo :: enum { Aa, Ab, Ac, Ad }
		main :: proc() {
			foo := Foo.{*}
	    }
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"Aa", "Ab", "Ac", "Ad"})
}


@(test)
ast_comp_lit_with_all_symbols_indexed_enum_implicit :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Foo :: enum {
			ONE,
			TWO,
		}
		
		Bar :: struct {
			a: int,
			b: int,
			c: Foo,
		}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		main :: proc() {
			a := my_package.Bar {
				c = .{*}
			}
	    }
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"TWO", "ONE"})
}

@(test)
ast_package_uppercase_test :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "My_package",
			source = `package My_package
		Foo :: enum {
			ONE,
			TWO,
		}
		
		Bar :: struct {
			a: int,
			b: int,
			c: Foo,
		}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "My_package"
		main :: proc() {
			My_package.{*}
	    }
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"My_package.Foo :: enum {..}", "My_package.Bar :: struct {..}"})
}


@(test)
ast_index_enum_infer :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package{pkg = "My_package", source = `package My_package
		Foo :: enum {
			ONE,
			TWO,
		}
		`},
	)

	source := test.Source {
		main     = `package main
		import "My_package"
		main :: proc() {
			my_enum: My_package.Foo

			if my_enum == {*}.
	    }
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"ONE", "TWO"})
}

@(test)
ast_index_enum_infer_call_expr :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Foo :: enum {
			ONE,
			TWO,
		}

		call :: proc(a: Foo) {}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"

		main :: proc() {
			my_package.call(.{*})
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"ONE", "TWO"})
}


@(test)
ast_index_builtin_ODIN_OS :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		main :: proc() {
			when ODIN_OS == .{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"Darwin"})
}

@(test)
ast_for_in_range_half_completion_1 :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		main :: proc() {
			ints: []int
		
			for int_idx in 0..<len(ints) {
				ints[int_idx] = int_i{*}
			}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"test.int_idx: int"})
}

@(test)
ast_for_in_range_half_completion_2 :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		advance_rune_n :: proc(t: ^Tokenizer, n: int) {
			for in 0..<n {
				advance_rune(n{*})
			}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"test.n: int"})
}

@(test)
ast_for_in_switch_type :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Foo :: struct {
			bar: int,
		}

		My_Struct :: struct {
			my: []My_Foo,
		}
		
		My_Union :: union {
			My_Struct,
		}
		
		main :: proc() {
			my_union: My_Union
			switch v in my_union {
			case My_Struct:
				for item in v.my {
					item.{*}
				}
			}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"My_Foo.bar: int"})
}

@(test)
ast_procedure_in_procedure_non_mutable_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		test :: proc() {
			Int :: int
			
			my_procedure_two :: proc() {
				b : In{*}
			}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.Int :: int"})
}

@(test)
ast_switch_completion_for_maybe_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			Maybe :: union($T: typeid) {T}

			My_Enum :: enum {
				One,
				Two,
			}
			main :: proc(a: Maybe(My_Enum)) {
				switch v in a {
					case My_Enum:
						switch v {
							case .{*}
						}
						
				}
			}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, ".", {"One", "Two"})
}

@(test)
ast_union_with_type_from_different_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package	
			My_Int :: int
		`})

	source := test.Source {
		main     = `package main
		import "my_package"

		My_Union :: union { 
			bool, 
			my_package.My_Int,
		}

		main :: proc() {
			my_union: My_Union
			my_union.{*} 
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_labels(t, &source, ".", {"(my_package.My_Int)"})
}

@(test)
ast_completion_union_with_typeid :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Maybe :: union($T: typeid) {T}

		main :: proc() {
			my_maybe: Maybe(typeid)
			my_maybe.{*}
		}
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"(typeid)"})
}

@(test)
ast_completion_with_pointer :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		main :: proc() {
			my_pointer: ^int
			my_p{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.my_pointer: ^int"})
}


@(test)
ast_matrix_completion_index :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			m := matrix[2, 3]f32 {
				1, 9, -13, 
				20, 5, -6, 
			}
		
			my_float := m[2, 3]
			my_f{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.my_float: f32"})
}

@(test)
ast_matrix_with_matrix_mult :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			a := matrix[2, 3]f32 {
				2, 3, 1, 
				4, 5, 0, 
			}
		
			b := matrix[3, 2]f32 {
				1, 2, 
				3, 4, 
				5, 6, 
			}

			my_matrix := a * b

			my_matri{*}		
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.my_matrix: matrix[2,2]f32"})
}

@(test)
ast_vector_with_matrix_mult :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		My_Matrix :: matrix[2, 4]f32

		main :: proc() {
			m := My_Matrix{1, 2, 3, 4, 5, 5, 4, 2}
			v := [4]f32{1, 5, 4, 3}
		
			my_vector := m * v
	
			my_vecto{*}		
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.my_vector: [4]f32"})
}

@(test)
ast_completion_on_call_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main		
		My_Struct :: struct {
			a: int,
			b: int,
		}

		my_function :: proc() -> My_Struct {}

		main :: proc() {
			my_function().{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"My_Struct.a: int", "My_Struct.b: int"})
}


@(test)
ast_completion_struct_with_same_name_in_pkg :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			A :: struct {
				lib_a: int,
				lib_b: int,
			}
			Nested :: struct {
				lib_a: A,
			}			
		`,
		},
	)

	source := test.Source {
		main     = `package test
		import "my_package"	
		A :: struct {
			main_a:int,
			main_b:int,
		}	
		main :: proc() {
			a := my_package.Nested{}
			a.lib_a.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"A.lib_a: int"})
}

@(test)
ast_completion_method_with_type :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			A :: struct {
				lib_a: int,
			}
			proc_one :: proc(a: ^A) {}
			proc_two :: proc(a: A) {}
		`,
		},
	)

	source := test.Source {
		main     = `package test
		import "my_package"	
		main :: proc() {
			a: my_package.A

			a.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"A.lib_a: int"})
}

@(test)
ast_implicit_bitset_value_decl_from_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			Foo :: enum { Aa, Ab, Ac, Ad }
			Foo_Set :: distinct bit_set[Foo; u32] 
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"

		
		Bar :: struct {
			foo: my_package.Foo_Set,
		}
		
		main :: proc() {
			foo_set := Bar { 
				foo = {.{*} } 
			}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_labels(t, &source, ".", {"Aa", "Ab", "Ac", "Ad"})
}

@(test)
ast_private_proc_ignore :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
				@(private)
				my_private :: proc() {}
	
				@private
				my_private_two :: proc() {}

			`,
		},
	)

	source := test.Source {
		main     = `package main
			import "my_package"
			main :: proc() {
				my_package.{*}
			}
			`,
		packages = packages[:],
	}

	test.expect_completion_labels(t, &source, ".", {})
}

@(test)
ast_bitset_assignment_diff_pkg :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			Foo :: enum { Aa, Ab, Ac, Ad }
			Foo_Set :: bit_set[Foo]
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		
		Bar :: struct {
			set: my_package.Foo_Set,
		}
		main :: proc() {
			s: Bar
			s.set = {.{*}}
	    }
		`,
		packages = packages[:],
	}

	test.expect_completion_labels(t, &source, ".", {"Aa", "Ab", "Ac", "Ad"})
}

@(test)
ast_local_global_function :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		import "my_package"

		main :: proc() {
			 my_function_two :: proc(one: int) {
				my_{*}
			 }
		
			 my_function_one :: proc(one: int) {
				
			 }
		
		}
		
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.my_function_two :: proc(one: int)"})
}

@(test)
ast_generic_struct_with_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Test :: struct($T: typeid) {
			values: [32]T,
		}
		
		Test_Inner :: struct {
			a, b, c: int,
		}
		
		main :: proc() {
			test := Test(Test_Inner) {}
			a := test.values[0]
			a.{*}
		}
		
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"Test_Inner.b: int"})
}

@(test)
ast_assign_to_global_function :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test	
		import "my_package"		
		get_foo :: proc() -> string {

		}
		
		global_foo := get_foo()
		
		main :: proc() {
			global_fo{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.global_foo: string"})
}

@(test)
ast_poly_dynamic_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test	
		import "my_package"		

		_raw_data_dynamic :: proc(data: $T/[dynamic]$E) -> [^]E {
			return {}
		}
		
		main :: proc() {
			my_dynamic: [dynamic]int
			ret_dynamic := _raw_data_dynamic(my_dynamic)
			ret_dy{*}	
		}
		
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.ret_dynamic: [^]int"})
}

@(test)
ast_poly_array_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test	
		import "my_package"		

		_raw_data_array :: proc(data: $T/[]$E) -> [^]E {
			return {}
		}
		
		main :: proc() {
			my_array: []int
			ret_array := _raw_data_array(my_array)
			ret_arr{*}	
		}
		
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.ret_array: [^]int"})
}

@(test)
ast_poly_struct_with_poly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Small_Array :: struct($N: int, $T: typeid) where N >= 0 {
			data: [N]T,
			len:  int,
		}

		Animal :: struct {
			happy:  bool,
			sad:    bool,
			fluffy: bool,
		}
		
		get_ptr :: proc "contextless" (a: ^$A/Small_Array($N, $T), index: int) -> ^T {
			return &a.data[index]
		}
		
		main :: proc() {
			animals := Small_Array(5, Animal){}
			first := get_ptr(&animals, 0)
			fir{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.first: ^test.Animal"})
}

@(test)
ast_poly_proc_array_constant :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		make_f32_array :: proc($N: int, $val: f32) -> (res: [N]f32) {
			for _, i in res {
				res[i] = val*val
			}
			return
		}

		main :: proc() {
			array := make_f32_array(3, 2)
			arr{*}
		}
		`,
	}


	test.expect_completion_docs(t, &source, "", {"test.array: [3]f32"})
}

@(test)
ast_poly_proc_matrix_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		matrix_to_ptr :: proc "contextless" (m: ^$A/matrix[$I, $J]$E) -> ^E {
			return &m[0, 0]
		}
		
		
		main :: proc() {	
			my_matrix: matrix[2, 2]f32	
			ptr := matrix_to_ptr(&my_matrix)
			pt{*}
		}
		
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.ptr: ^f32"})
}

@(test)
ast_poly_proc_matrix_constant_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		matrix_to_ptr :: proc "contextless" (m: ^$A/matrix[$I, $J]$E) -> [J]E {
			return {}
		}
		
		main :: proc() {
			my_matrix: matrix[4, 3]f32
		
			ptr := matrix_to_ptr(&my_matrix)
			pt{*}	
		}	
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.ptr: [3]f32"})
}

@(test)
ast_poly_proc_matrix_constant_array_2 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		array_cast :: proc "contextless" (
			v: $A/[$N]$T,
			$Elem_Type: typeid,
		) -> (
			w: [N]Elem_Type,
		) {
			for i in 0 ..< N {
				w[i] = Elem_Type(v[i])
			}
			return
		}
		main :: proc() {
			my_vector: [10]int
			myss := array_cast(my_vector, f32)
			mys{*}
		}	
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.myss: [10]f32"})
}

@(test)
ast_poly_proc_matrix_whole :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		
		@(require_results)
		matrix_mul :: proc "contextless" (
			a, b: $M/matrix[$N, N]$E,
		) -> (
			c: M,
		) where !IS_ARRAY(E),
			IS_NUMERIC(E) #no_bounds_check {
			return a * b
		}

		matrix4_from_trs_f16 :: proc "contextless" () -> matrix[4, 4]f32 {
			translation: matrix[4, 4]f32
			rotation: matrix[4, 4]f32
			dsszz := matrix_mul(rotation, translation)
			dssz{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.dsszz: matrix[4,4]f32"})

}

@(test)
ast_completion_comp_lit_in_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Struct :: struct {
				one: int,
				two: int,
			}

			my_function :: proc(my_struct: My_Struct) {

			}

			main :: proc() {
				my_function({on{*}})
			}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"My_Struct.one: int"})
}


@(test)
ast_completion_infer_bitset_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			My_Enum :: enum {
				ONE,
				TWO,
			}
			My_Bitset :: bit_set[My_Enum]
		`,
		},
	)

	source := test.Source {
		main     = `package test	
			import "my_package"	

			my_function :: proc(my_bitset: my_package.My_Bitset)

			main :: proc() {
				my_function({.{*}})
			}
		`,
		packages = packages[:],
	}

	test.expect_completion_labels(t, &source, ".", {"ONE", "TWO"})
}

@(test)
ast_simple_bit_field_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		My_Bit_Field :: bit_field uint {
			one: int | 1,
			two: int | 1,
			three: int | 1,
		}

		main :: proc() {
			my_bit_field: My_Bit_Field;
			my_bit_field.{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(
		t,
		&source,
		".",
		{"My_Bit_Field.one: int", "My_Bit_Field.two: int", "My_Bit_Field.three: int"},
	)
}

@(test)
ast_simple_union_of_enums_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
			Sub_Enum_1 :: enum {
				ONE,
			}
			Sub_Enum_2 :: enum {
				TWO,
			}

			Super_Enum :: union {
				Sub_Enum_1,
				Sub_Enum_2,
			}

			fn :: proc(mode: Super_Enum) {}

			main :: proc() {
				fn(.{*})
			}
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"Sub_Enum_1.ONE", "Sub_Enum_2.TWO"})
}


@(test)
ast_generics_function_with_struct_same_pkg :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			DummyFunction :: proc(value: $T/[dynamic]$E, index: int) -> ^E
			{
				return &value[index]
			}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		
		CoolStruct :: struct
		{
			val1, val2, val3: int,
		}

		main :: proc()
		{
			testArray : [dynamic]CoolStruct
			
			//no completion on function or new value
			newValue := my_package.DummyFunction(testArray, 10)
			newValue.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(
		t,
		&source,
		".",
		{"CoolStruct.val1: int", "CoolStruct.val2: int", "CoolStruct.val3: int"},
	)
}


@(test)
ast_generics_function_with_struct_diff_pkg :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			DummyFunction :: proc(value: $T/[dynamic]$E, index: int) -> ^E
			{
				return &value[index]
			}

			CoolStruct :: struct
			{
				val1, val2, val3: int,
			}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		
		main :: proc()
		{
			testArray : [dynamic]my_package.CoolStruct
			
			//no completion on function or new value
			newValue := my_package.DummyFunction(testArray, 10)
			newValue.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(
		t,
		&source,
		".",
		{"CoolStruct.val1: int", "CoolStruct.val2: int", "CoolStruct.val3: int"},
	)
}


@(test)
ast_generics_function_with_comp_lit_struct :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			DummyFunction :: proc($T: typeid, value: T) -> T
			{
				return value;
			}	

			OtherStruct :: struct 
			{
				val1, val2, val3: int,
			}
		`,
		},
	)

	source := test.Source {
		main     = `package main
		import "my_package"
		
		CoolStruct :: struct
		{
			val1, val2, val3: int,
		}

		main :: proc()
		{
			newValue := my_package.DummyFunction(CoolStruct, CoolStruct{})
    		newValue.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(
		t,
		&source,
		".",
		{"CoolStruct.val1: int", "CoolStruct.val2: int", "CoolStruct.val3: int"},
	)
}

@(test)
ast_generics_struct_poly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
	Pair :: struct($A, $B: typeid) {
		a: A,
		b: B,
	}

	Foo :: struct {
		cool: int,
	}

	select :: proc($T: typeid, search: []Pair(string, any), allocator := context.temp_allocator) -> []T {

	}


	main :: proc() {
		d := select(Foo, []Pair(string, any){})
		d[0].c{*}
	}
	`,
	}

	test.expect_completion_docs(t, &source, ".", {"Foo.cool: int"})

}

@(test)
ast_generics_pointer_poly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		AAA :: struct($T: typeid) {
			value: ^T,
		}

		main :: proc() {
			ttt: AAA(int)
			ttt.{*}
		}
	`,
	}

	test.expect_completion_docs(t, &source, ".", {"AAA.value: ^int"})

}


@(test)
ast_enumerated_array_index_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Direction :: enum {
			North,
			East,
			South,
			West,
		}

		Direction_Vectors :: [Direction][2]int {
			.North = {0, -1},
			.East  = {+1, 0},
			.South = {0, +1},
			.West  = {-1, 0},
		}

		main :: proc() {
			Direction_Vectors[.{*}]
		}
		`,
	}

	test.expect_completion_labels(t, &source, ".", {"North", "East", "South", "West"})
}


@(test)
ast_enumerated_array_range_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Enum :: enum {
			Foo,
			Bar,
			Baz,
		}

		ARRAY :: [Enum]string{
			.Foo = "foo",
			.Bar = "bar",
			.Baz = "baz",
		}

		main :: proc() {
			for item, indezx in ARRAY {
				indez{*} 
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.indezx: test.Enum"})
}

@(test)
ast_raw_data_slice :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		_raw_data_slice   :: proc(value: []$E)         -> [^]E    {}
		_raw_data_dynamic :: proc(value: [dynamic]$E)  -> [^]E    {}
		_raw_data_array   :: proc(value: ^[$N]$E)      -> [^]E    {}
		_raw_data_simd    :: proc(value: ^#simd[$N]$E) -> [^]E    {}
		_raw_data_string  :: proc(value: string)       -> [^]byte {}

		_raw_data :: proc{_raw_data_slice, _raw_data_dynamic, _raw_data_array, _raw_data_simd, _raw_data_string}

		main :: proc() {
			slice: []int
			rezz := _raw_data(slice)
			rez{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.rezz: [^]int"})
}

@(test)
ast_raw_data_slice_2 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		raw_data_slice :: proc(v: $T/[]$E) -> [^]E {}


		cool :: proc {
			raw_data_slice,
		}

		main :: proc() {
			my_slice: []int
			rezz := cool(my_slice)
			rez{*}
		}

		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.rezz: [^]int"})
}

@(test)
ast_switch_completion_multiple_cases :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		main :: proc() {
			switch {
			case true:
				foozz: int
			case false:
				fooz{*}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {})
}


@(test)
ast_generics_chained_procedures :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		foo :: proc (v: int) -> int {
			return v
		}

		bar :: proc (v: $T) -> T {
			return v
		}

		main :: proc () {
			valzz := bar(foo(123))
			valz{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.valzz: int"})
}

@(test)
ast_generics_untyped_int_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		foo :: proc(x: $T) -> T {
			return x + 1
		}

		test :: proc() {
			valzz := foo(2)
			valz{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.valzz: int"})
}

@(test)
ast_generics_untyped_bool_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		foo :: proc(x: $T) -> T {
			return x + 1
		}

		test :: proc() {
			valzz := foo(false)
			valz{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.valzz: bool"})
}


@(test)
ast_generics_call_reference_comp_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Foo :: struct {
			something: f32,
			bar:       ^Bar,
		}

		Bar :: struct {
			something_else: i32,
		}

		my_proc :: proc(foo: ^Foo) {

		}

		main :: proc() {
			my_proc(&{bar = &Bar{ {*} }})
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Bar.something_else: i32"})
}

@(test)
ast_completion_on_struct_using_field_selector :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		Inner :: struct {
			field: int,
		}
		Outer :: struct {
			using inner: Inner,
		}

		main :: proc() {
			data: Outer
			data.inner.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, ".", {"Inner.field: int"})
}

@(test)
ast_completion_on_struct_using_field_selector_directly :: proc(t: ^testing.T) {
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
			using ii: InnerInner,
		}

		Outer :: struct {
			using inner: Inner,
		}

		`,
		},
	)
	source := test.Source {
		main     = `package main
		import "my_package"


		main :: proc() {
			data: my_package.Outer
			data.{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"Outer.field: int"})
}

@(test)
ast_completion_on_string_iterator :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
		split_lines_iterator :: proc(s: ^string) -> (line: string, ok: bool) {
		}

		main :: proc() {
			s: string

			for linze in split_lines_iterator(&s) {
				linz{*}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.linze: string"})
}

@(test)
ast_completion_multi_pointer :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		S1 :: struct {
			s2_ptr: [^]S2,
		}

		S2 :: struct {
			field: int,
		}

		main :: proc() {
			x := S1 {
				s2_ptr = &S2 {
					{*}
				}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"S2.field: int"})
}

@(test)
ast_completion_multi_pointer_nested :: proc(t: ^testing.T) {
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
					field = S3 {
						{*}
					}
				}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"S3.s3: int"})
}

@(test)
ast_completion_struct_documentation :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			My_Struct :: struct {
			}
		`})
	source := test.Source {
		main     = `package main

		import "my_package"

		Foo :: struct {
			bazz: my_package.My_Struct // bazz
		}

		main :: proc() {
			p := Foo{}
			p.b{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, "", {"Foo.bazz: my_package.My_Struct\n---\nbazz"})
}

@(test)
ast_completion_inline_using :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		Foo :: struct {
			using _ : struct {
				a: int,
				b: int,
			}
		}

		main :: proc() {
			foo := Foo{}
			foo.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Foo.a: int", "Foo.b: int"})
}

@(test)
ast_completion_vtable_using :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		IUnknown :: struct {
			using _iunknown_vtable: ^IUnknown_VTable,
		}

		IUnknownVtbl :: IUnknown_VTable
		IUnknown_VTable :: struct {
			QueryInterface: proc "system" (This: ^IUnknown, riid: REFIID, ppvObject: ^rawptr) -> HRESULT,
			AddRef:         proc "system" (This: ^IUnknown) -> ULONG,
			Release:        proc "system" (This: ^IUnknown) -> ULONG,
		}

		main :: proc() {
			foo: ^IUnknown
			foo->{*}
		}
		`,
	}

	test.expect_completion_docs(
		t,
		&source,
		"->",
		{
			`IUnknown.QueryInterface: proc "system" (This: ^IUnknown, riid: REFIID, ppvObject: ^rawptr) -> HRESULT`,
			`IUnknown.AddRef: proc "system" (This: ^IUnknown) -> ULONG`,
			`IUnknown.Release: proc "system" (This: ^IUnknown) -> ULONG`,
		},
	)
}

@(test)
ast_complete_ptr_using :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

		B :: struct {
			foo: int,
		}

		A :: struct {
			using b: ^B,
			using a: ^struct {
				f: int,
			},
		}

		main :: proc() {
			foo: A
			foo.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {`A.b: ^test.B`, `A.a: ^struct {..}`, `A.foo: int`, `A.f: int`})
}

@(test)
ast_completion_poly_struct_another_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Runner :: struct($TState: typeid) {
			state: TState, // state
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test

		import "my_package"

		app: my_package.Runner(State) = {
			state = {score = 55},
		}

		main :: proc() {
			app.{*}
		}

		State :: struct {
			score: int,
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, "", {"Runner.state: test.State\n---\nstate"})
}

@(test)
ast_completion_poly_struct_another_package_field :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Runner :: struct($TState: typeid) {
			state: TState, // state
		}
		`,
		},
	)
	source := test.Source {
		main     = `package test

		import "my_package"

		app: my_package.Runner(State) = {
			state = {score = 55},
		}

		main :: proc() {
			app.state.{*}
		}

		State :: struct {
			score: int,
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, "", {"State.score: int"})
}

@(test)
ast_completion_poly_proc_mixed_packages :: proc(t: ^testing.T) {
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
			f := foo_package.foo(b)
			f.{*}
		}
	}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, "", {"Bar.bar: int"})
}

@(test)
ast_completion_enum_slice :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		E :: enum { A, B }
		Eslice :: []E

		main :: proc() {
			a: Eslice = { .{*} }
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_enum_bitset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		E :: enum { A, B, C }

		Ebitset :: bit_set[E]

		main :: proc() {
			b: Ebitset = { .A, .C, .{*} }
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"B"}, {"A", "C"})
}

@(test)
ast_completion_enum_map_key :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		E :: enum { A, B, C }

		M :: map[E]int

		main :: proc() {
			m: M
			m[.{*}]
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B", "C"})
}

@(test)
ast_completion_enum_bitset_with_adding_values :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		Foos :: bit_set[Foo]

		main :: proc() {
			foos: Foos
			foos += {.A, .{*}}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"B"}, {"A"})
}

@(test)
ast_completion_enumerated_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		Bar :: struct {}

		db_data: [Foo]Bar = {
			.{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo1", "Foo2"})
}

@(test)
ast_completion_enumerated_array_should_exclude_already_added :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		Bar :: struct {}

		db_data: [Foo]Bar = {
			.Foo1 = {},
			.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Foo2"}, {"Foo1"})
}

@(test)
ast_completion_enumerated_array_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		Bar :: struct {
			bar: int,
		}

		db_data: [Foo]Bar = {
			.Foo1 = {
				{*}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Bar.bar: int"})
}

@(test)
ast_completion_nested_enumerated_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		Bar :: struct {
			bar: int,
		}

		db_data: [Foo][Foo]Bar = {
			.Foo1 = {
				.Foo2 = {},
				{*}
			},
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"test.Foo: .Foo1"}, {"test.Foo: .Foo2"})
}

@(test)
ast_completion_enumerated_array_implicit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		Bar :: struct {
			bar: int,
		}

		db_data: [Foo]Bar = {
			.Foo2 = {},
			.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Foo1"}, {"Foo2"})
}

@(test)
ast_completion_nested_enumerated_array_struct_fields :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Foo1,
			Foo2,
		}

		Bar :: struct {
			bar: int,
			bar2: string,
		}

		db_data: [Foo][Foo]Bar = {
			.Foo1 = {
				.Foo2 = {
					{*}
				},
			},
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Bar.bar: int", "Bar.bar2: string"})
}

@(test)
ast_completion_union_switch_remove_used_cases :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo1 :: struct{}
		Foo2 :: struct{}
		Foo3 :: struct{}
		Foo :: union {
			Foo1,
			Foo2,
			Foo3,
		}

		main :: proc() {
			foo: Foo

			switch v in Foo {
			case Foo1:
			case F{*}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Foo2", "Foo3"}, {"Foo1"})
}

@(test)
ast_completion_union_switch_remove_used_cases_ptr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo1 :: struct{}
		Foo2 :: struct{}
		Foo3 :: struct{}
		Foo :: union {
			^Foo1,
			^Foo2,
			^Foo3,
		}

		main :: proc() {
			foo: Foo

			switch v in Foo {
			case ^Foo1:
			case F{*}
			}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"^Foo2", "^Foo3"}, {"^Foo1"})
}

@(test)
ast_completion_struct_field_value_when_not_specifying_type_at_use_implicit :: proc(t: ^testing.T) {
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
				foo = .{*}
			}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_struct_field_enum :: proc(t: ^testing.T) {
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
			bar: Bar
			bar.{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Bar.foo: test.Foo"})
}

@(test)
ast_completion_proc_enum_param :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B
		}

		bar :: proc(a, b: int, foo: Foo) {}

		main :: proc() {
			bar(1, 1, .{*})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_using_aliased_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			foo :: proc() {}
		`})

	source := test.Source {
		main     = `package test

		import "my_package"
		mp :: my_package

		main :: proc() {
			using mp
			f{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"my_package.foo :: proc()"})
}

@(test)
ast_completion_using_aliased_package_multiple :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "foo_pkg", source = `package foo_pkg
			foo :: proc() {}
		`})

	append(&packages, test.Package{pkg = "bar_pkg", source = `package bar_pkg
			bar :: proc() {}
		`})

	source := test.Source {
		main     = `package test

		import "foo_pkg"
		import "bar_pkg"
		fp :: foo_pkg

		main :: proc() {
			using fp
			f{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, ".", {"foo_pkg.foo :: proc()"})
}

@(test)
ast_completion_bitset_if_statement_in :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			AAA,
			AAB
		}

		Bar :: bit_set[Foo]

		main :: proc() {
			bar: Bar
			if .A{*} in bar {

			}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"AAA", "AAB"})
}

@(test)
ast_completion_bitset_named_proc_arg :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: bit_set[Foo]

		foo :: proc(i: int = 0, bar: Bar = {})

		main :: proc() {
			foo(bar = {.{*}})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_bitset_named_proc_arg_should_remove_already_used :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: bit_set[Foo]

		foo :: proc(i: int = 0, bar: Bar = {})

		main :: proc() {
			foo(bar = {.A, .{*}})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"B"}, {"A"})
}

@(test)
ast_completion_return_comp_lit_enum :: proc(t: ^testing.T) {
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
				foo = .{*}
			}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_return_nested_comp_lit_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foo: Foo,
		}

		Bazz :: struct {
			bar: Bar,
		}

		foo :: proc() -> Bazz {
			return {
				bar = {
					foo = .{*}
				}
			}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_enum_global_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			id: int,
			foo: Foo,
		}

		bars: []Bar = {
			{
				foo = .{*}
			},
		}
	`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_enum_array_in_proc_param :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		bar :: proc(v: i32) {}

		main :: proc() {
			foos: [Foo]i32
			bar(foos[.{*}])
		}
	`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_union_with_poly :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: union($T: typeid) {
			T,
		}

		main :: proc() {
			foo: Foo(int)
			f{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.foo: test.Foo(int)"})
}

@(test)
ast_completion_union_with_poly_from_package :: proc(t: ^testing.T) {
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
			foo: my_package.Foo(int)
			f{*}
		}
		`,
		packages = packages[:],
	}
	test.expect_completion_docs(t, &source, "", {"test.foo: my_package.Foo(int)"})
}

@(test)
ast_completion_chained_proc_call_params :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			data: int,
		}

		main :: proc() {
			foo()({{*}})
		}

		foo :: proc() -> proc(data: Foo) -> bool {
			return bar
		}

		bar :: proc(data: Foo) -> bool {
			return false
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.data: int"})
}

@(test)
ast_completion_multiple_chained_call_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			someData: int,
		}

		Bazz :: struct {
			bazz: string,
		}

		main :: proc() {
			a := foo()({})({{*}})
		}

		Bar :: proc(data: Foo) -> Bar2

		Bar2 :: proc(bazz: Bazz) -> int

		foo :: proc() -> Bar {}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Bazz.bazz: string"})
}

@(test)
ast_completion_nested_struct_with_enum_fields_unnamed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo1 :: enum {
			A, B,
		}

		Foo2 :: enum {
			C, D,
		}

		Foo3 :: struct {
			foo3: string,
		}

		Bar :: struct {
			foo1: Foo1,
			foo2: Foo2,
			foo3: Foo3,
		}

		Bazz :: struct {
			bar: Bar,
		}

		main :: proc() {
			bazz := Bazz {
				bar = {.A, .{*}, {}}
			}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"C", "D"}, {"A", "B"})
}

@(test)
ast_completion_poly_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(array: $A/[]$T) {
			for elem, i in array {
				el{*}
			}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.elem: $T"})
}

@(test)
ast_completion_proc_field_names :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(i: int, bar := "") {}

		main :: proc() {
			foo(b{*})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.bar: string"})
}

@(test)
ast_completion_enum_variadiac_args :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
			C,
		}

		foo :: proc(foos: ..Foo) {}

		main :: proc() {
			foo(.A, .{*})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B", "C"})
}

@(test)
ast_completion_proc_variadiac_arg :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
			C,
		}

		foo :: proc(foos: ..{*}) {}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.Foo :: enum {..}"})
}

@(test)
ast_completion_within_struct_decl :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
			C,
		}

		foo :: proc(f: Foo) {}

		Bar :: struct {
			bar: f{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.Foo :: enum {..}"}, {"test.foo :: proc(f: Foo)"})
}

@(test)
ast_completion_enum_map_key_global :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		E :: enum { A, B, C }

		m: map[E]int = {
			.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B", "C"})
}

@(test)
ast_completion_enum_map_key_global_with_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		E :: enum { A, B, C }

		m: map[E]int = {
			.{*} = 0,
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B", "C"})
}

@(test)
ast_completion_enum_map_value_global :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		E :: enum { A, B, C }

		m: map[int]E = {
			0 = .A,
			1 = .{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B", "C"})
}

@(test)
ast_completion_basic_type_other_pkg :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			foo: int
		`})
	source := test.Source {
		main     = `package test
		import "my_package"

		foo :: proc() {
			my_package.f{*}
		}
		`,
		packages = packages[:],
	}

	test.expect_completion_docs(t, &source, "", {"my_package.foo: int"})
}

@(test)
ast_completion_soa_slice_fields :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x: int,
			y: string,
		}

		main :: proc() {
			foos: #soa[]Foo
			foos.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"foos.x: [^]int", "foos.y: [^]string"})
}

@(test)
ast_completion_soa_fixed_array_fields :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x: int,
			y: string,
		}

		main :: proc() {
			foos: #soa[3]Foo
			foos.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"foos.x: [3]int", "foos.y: [3]string"})
}

@(test)
ast_completion_soa_pointer :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x: int,
			y: string,
		}

		main :: proc() {
			foos: #soa^#soa[3]Foo
			foos.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"Foo.x: int", "Foo.y: string"})
}

@(test)
ast_completion_bit_set_in_not_in :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			foos: bit_set[Foo]
			foos.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {".A in foos", ".A not_in foos", ".B in foos", ".B not_in foos"})
}

@(test)
ast_completion_bit_set_type_in_not_in :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}
		Foos :: bit_set[Foo]

		main :: proc() {
			foos: Foos
			foos.{*}
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {".A in foos", ".A not_in foos", ".B in foos", ".B not_in foos"})
}

@(test)
ast_completion_bit_set_on_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foos: bit_set[Foo],
		}

		main :: proc() {
			bar: Bar
			bar.foos.{*}
		}
		`,
	}

	test.expect_completion_docs(
		t,
		&source,
		"",
		{".A in bar.foos", ".A not_in bar.foos", ".B in bar.foos", ".B not_in bar.foos"},
	)
}

@(test)
ast_completion_handle_matching_basic_types :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		bar :: proc(i: ^int) {}

		main :: proc() {
			foo: int
			bar(f{*})
		}
		`,
		config = {enable_completion_matching = true},
	}
	test.expect_completion_insert_text(t, &source, "", {"&foo"})
}

@(test)
ast_completion_handle_matching_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct{}

		bar :: proc(foo: ^Foo) {}

		main :: proc() {
			foo: Foo
			bar(f{*})
		}
		`,
		config = {enable_completion_matching = true},
	}
	test.expect_completion_insert_text(t, &source, "", {"&foo"})
}

@(test)
ast_completion_handle_matching_append :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			foos: [dynamic]int
			append(fo{*})
		}
		`,
		config = {enable_completion_matching = true},
	}
	test.expect_completion_insert_text(t, &source, "", {"&foos"})
}

@(test)
ast_completion_handle_matching_dynamic_array_to_slice :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		bar :: proc(b: []int)

		main :: proc() {
			foos: [dynamic]int
			bar(fo{*})
		}
		`,
		config = {enable_completion_matching = true},
	}
	test.expect_completion_insert_text(t, &source, "", {"foos[:]"})
}

@(test)
ast_completion_proc_bit_set_comp_lit_default_param_with_no_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		Foos :: distinct bit_set[Foo]

		bar :: proc(foos := Foos{}) {}

		main :: proc() {
			bar({.{*}})
		}
		`,
	}

	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_handle_matching_from_overloaded_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			a: int,
		}

		get_foo :: proc {
			get_foo_none,
			get_foo_a,
		}

		get_foo_none :: proc() -> Foo {
			return Foo{}
		}

		get_foo_a :: proc(a: int) -> Foo {
			return Foo{
				a = a,
			}
		}

		do_foo :: proc(foo: ^Foo) {}

		main :: proc() {
			foo := get_foo()
			do_foo(f{*})
		}
		`,
		config = {enable_completion_matching = true},
	}
	test.expect_completion_insert_text(t, &source, "", {"&foo"})
}

@(test)
ast_completion_poly_proc_narrow_type :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {x, y: i32}

		foo :: proc (a: $T/F{*}) {}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.Foo :: struct {..}"})
}

@(test)
ast_completion_union_with_enums :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A, B,
		}

		Bar :: enum {
			A, C,
		}

		Bazz :: union #shared_nil {
			Foo,
			Bar,
		}

		main :: proc() {
			bazz: Bazz
			if bazz == .F{*} {}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.A", "Foo.B", "Bar.A", "Bar.C"})
}

@(test)
ast_completion_union_with_enums_from_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Foo :: enum {
			A, B,
		}

		Bar :: enum {
			A, C,
		}

		Bazz :: union #shared_nil {
			Foo,
			Bar,
		}
		`,
		},
	)

	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {
			bazz: my_package.Bazz
			if bazz == .{*} {}
		}
		`,
		packages = packages[:],
	}
	test.expect_completion_docs(
		t,
		&source,
		"",
		{"my_package.Foo.A", "my_package.Foo.B", "my_package.Bar.A", "my_package.Bar.C"},
	)
}

@(test)
ast_completion_struct_field_name :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct{}

		Bar :: struct {
			f{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {}, {"test.Foo :: struct{}"})
}

@(test)
ast_completion_struct_field_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct{}

		Bar :: struct {
			foo: F{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.Foo :: struct{}"})
}

@(test)
ast_completion_handle_matching_with_unary :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct{}

		do_foo :: proc(foo: ^Foo){}

		main :: proc() {
			foo: Foo
			do_foo(&f{*})
		}
		`,
		config = {
			enable_completion_matching = true,
		},
	}
	test.expect_completion_insert_text(t, &source, "", {"foo"})
}

@(test)
ast_completion_handle_matching_field_with_unary :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct{}

		do_foo :: proc(foo: ^Foo){}

		main :: proc() {
			foo: Foo
			do_foo(foo = &f{*})
		}
		`,
		config = {
			enable_completion_matching = true,
		},
	}
	test.expect_completion_insert_text(t, &source, "", {"foo"})
}

@(test)
ast_completion_overload_proc_returning_proc_complete_comp_lit_arg_local :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			bar: int,
			bazz: string,
		}

		foo_none :: proc() -> proc(config: Foo) -> bool {}
		foo_string :: proc(s: string) -> proc(config: Foo) -> bool {}

		foo :: proc{foo_none, foo_string}

		main :: proc() {
			result := foo()
			result({
				{*}
			})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bar: int", "Foo.bazz: string"})
}

@(test)
ast_completion_overload_proc_returning_proc_complete_comp_lit_arg_direct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			bar: int,
			bazz: string,
		}

		foo_none :: proc() -> proc(config: Foo) -> bool {}
		foo_string :: proc(s: string) -> proc(config: Foo) -> bool {}

		foo :: proc{foo_none, foo_string}

		main :: proc() {
			foo()({
				{*}
			})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bar: int", "Foo.bazz: string"})
}

@(test)
ast_completion_array_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			foo1 := 1
			foo2 := 2

			foos: [2]int
			foos = {{*}}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.foo1: int", "test.foo2: int"})
}

@(test)
ast_completion_named_proc_arg_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: int,
		}

		bazz :: proc(foos: []Foo = {}, bars: []Bar = {}) {}

		main :: proc() {
			bazz(bars = {
				{
					{*}
				}
			})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Bar.bar: int"})
}

@(test)
ast_completion_fixed_array_enum :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
			C,
		}

		foos := [3]Foo {
			.{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B", "C"})
}

@(test)
ast_completion_proc_enum_default_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
			C,
		}

		bar :: proc(foo := Foo.A) {}

		main :: proc() {
			bar(.{*})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B", "C"})
}

@(test)
ast_completion_cast_rawptr_selector :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
			bar: bool,
		}

		Baz :: struct {
			foo: Foo,
		}

		main :: proc() {
			baz: Baz
			baz_ptr := &baz
			foo_ptr := (cast(^Foo)rawptr(baz_ptr)).{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bar: bool"})
}

@(test)
ast_completion_local_when_condition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			when true {
				foo : i32 = 5
			} else {
				foo : i64 = 6
			}
			fo{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.foo: i32"})
}

@(test)
ast_completion_local_when_condition_false :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		main :: proc() {
			when false {
				foo : i32 = 5
			} else {
				foo : i64 = 6
			}
			fo{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"test.foo: i64"})
}

@(test)
ast_completion_selector_after_selector_call_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Data :: struct {
			x, y: int,
		}

		IFoo :: struct {
			bar: proc(self: IFoo, x: int),
		}

		print :: proc(self: IFoo, x: int) {}

		main :: proc() {
			data := Data{3, 4}
			foo := IFoo {
				bar = print,
			}
			foo->bar(data.{*})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Data.x: int", "Data.y: int"})
}

@(test)
ast_completion_empty_selector_before_label :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
		  bar: int,
		}

		main :: proc() {
		  foo: Foo
		  foo.{*}

		  Label: {

		  }
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bar: int"})
}

@(test)
ast_completion_empty_selector_if_init :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
		  bar: int,
		}

		main :: proc() {
		  foo: Foo
		  if bar := foo.{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bar: int"})
}

@(test)
ast_completion_empty_selector_switch_init :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Bar :: enum {
			A, B,
		}

		Foo :: struct {
		  bar: Bar,
		}

		main :: proc() {
		  foo: Foo
		  switch bar := foo.{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bar: test.Bar"})
}

@(test)
ast_completion_empty_selector_for_init :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: struct {
		  bars: [5]int,
		}

		main :: proc() {
		  foo: Foo
		  for bars := foo.{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bars: [5]int"})
}

@(test)
ast_completion_union_option_with_using :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Foo :: struct{}

		Bar :: struct{}

		Bazz :: union {
			^Foo,
			^Bar,
		}
		`,
		},
	)
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			using my_package

			bazz: Bazz
			if foo, ok := bazz.{*}
		}
		`,
		packages = packages[:],
	}
	test.expect_completion_labels(t, &source, "", {"(^Foo)", "(^Bar)"})
}

@(test)
ast_completion_implicit_selector_enumerated_array_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		A :: enum {
			A1,
			A2,
		}

		B :: enum {
			B1,
			B2,
		}

		A_TO_B :: [A]B{
			.A1 = .{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"B1", "B2"})
}

@(test)
ast_completion_implicit_selector_enumerated_array_in_proc_call_arg :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		A :: enum {
			A1,
			A2,
		}

		B :: enum {
			B1,
			B2,
		}

		A_TO_B :: [A]B{}

		foo :: proc(b: B) {}

		main :: proc() {
			foo(A_TO_B[.{*}])

		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A1", "A2"})
}

@(test)
ast_completion_implicit_selector_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}
		main :: proc() {
			foo: Foo
			if foo < .{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_global_selector_from_local_scope :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			foo: int,
		}

		FOO :: Foo{}

		main :: proc() {
			FOO.{*}
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.foo: int"})
}

@(test)
ast_completion_empty_selector_with_ident_newline :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
		Foo :: struct{}
		`,
		},
	)
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			my_package.{*}
			y := 2
		}
		`,
		packages = packages[:],
	}
	test.expect_completion_docs(t, &source, "", {"my_package.Foo :: struct{}"})
}

@(test)
ast_completion_implicit_selector_binary_expr_proc_call :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(
		&packages,
		test.Package {
			pkg = "my_package",
			source = `package my_package
			Foo :: enum {
				A,
				B,
				C,
			}

			Bar :: enum {
				X,
				Y,
			}

			foo :: proc(f: Foo) -> bit_set[Bar] {
				return {.X}
			}
		`,
		},
	)
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			results: bit_set[my_package.Bar]

			results |= my_package.foo(.{*})
		}
		`,
		packages = packages[:],
	}
	test.expect_completion_labels(t, &source, "", {"A", "B", "C"}, {"X", "Y"})
}

@(test)
ast_completion_proc_arg_default_enum_alias :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		Bar :: Foo.A

		foo :: proc(f := Bar) {}

		main :: proc() {
			foo(.{*})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_proc_group_bitset :: proc(t: ^testing.T) {
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
			foo(1, {.{*}})
		}
		`,
	}
	test.expect_completion_docs(t, &source, "", {"A", "B"})
}

@(test)
ast_completion_struct_using_anonymous_vector_types :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			using _: [3]f32,
		}

		main :: proc() {
			foo: Foo
			foo.{*}
		}

		`,
	}
	test.expect_completion_docs(t, &source, "", {"r: f32", "x: f32"})
}

@(test)
ast_completion_struct_using_named_vector_types :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			using bar: [3]f32,
		}

		main :: proc() {
			foo: Foo
			foo.{*}
		}

		`,
	}
	test.expect_completion_docs(t, &source, "", {"Foo.bar: [3]f32", "r: f32", "x: f32"})
}
