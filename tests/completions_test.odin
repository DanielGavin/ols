package tests

import "core:testing"
import "core:fmt"

import test "shared:testing"

@(test)
ast_simple_struct_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: My_Struct;
			my_struct.*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_index_array_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: [] My_Struct;
			my_struct[2].*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_pointer_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: ^My_Struct;
			my_struct.*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_take_address_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: My_Struct;
			my_pointer := &my_struct;
			my_pointer.*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_struct_deref_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_struct: ^^My_Struct;
			my_deref := my_struct^;
			my_deref.*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_range_map :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_map: map[int]My_Struct;
			
			for key, value in my_map {
				value.*
			}

		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_range_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_array: []My_Struct;
			
			for value in my_array {
				value.*
			}

		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int", "My_Struct.three: int"});
}

@(test)
ast_completion_identifier_proc_group :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

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
			grou*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.group_function: proc"});
}

@(test)
ast_completion_in_comp_lit_type :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}

		main :: proc() {
			my_comp := M* {

			};
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.My_Struct: struct"});
}

@(test)
ast_completion_range_struct_selector_strings :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		My_Struct :: struct {
			array: []string,
		}

		main :: proc() {
			my_struct: My_Struct;
	
			for value in my_struct.array {
				val*
			}
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.value: string"});
}

@(test)
ast_completion_selector_on_indexed_array :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		My_Foo :: struct {
			a: int,
			b: int,
		}

		My_Struct :: struct {
			array: []My_Foo,
		}

		main :: proc() {
			my_struct: My_Struct;
	
			my_struct.array[len(my_struct.array)-1].*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Foo.a: int", "My_Foo.b: int"});
}

@(test)
index_package_completion :: proc(t: ^testing.T) {

	packages := make([dynamic]test.Package);

	append(&packages, test.Package {
		pkg = "my_package",
		source = `package my_package
		My_Struct :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
	});

    source := test.Source {
		main = `package test

		import "my_package"

		main :: proc() {	
            my_package.*
		}
		`,
		packages = packages[:],
	};

    test.expect_completion_details(t, &source, ".", {"my_package.My_Struct: struct"});
}

import "core:odin/ast"
import "core:odin/parser"

@(test)
ast_generic_make_slice :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		Allocator :: struct {

		}
		Context :: struct {
			allocator: Allocator,
		}
		make_slice :: proc($T: typeid/[]$E, auto_cast len: int, allocator := context.allocator, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}

		My_Struct :: struct {
			my_int: int,
		}

		main :: proc() {
			my_slice := make_slice([]My_Struct, 23);
			my_slic*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.my_slice: []My_Struct"});
}

@(test)
ast_named_procedure_1 :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test
		proc_a :: proc(a: int, b: int) -> int {
		}

		proc_b :: proc(a: int, b: bool) -> bool {
		}

		my_group :: proc {proc_a, proc_b};

		main :: proc() {
			my_bool := my_group(b = false, a = 2);
			my_boo*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.my_bool: bool"});
}

@(test)
ast_named_procedure_2 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		proc_a :: proc(a: int, b: int) -> int {
		}

		proc_b :: proc(a: int, b: bool) -> bool {
		}

		my_group :: proc {proc_a, proc_b};

		main :: proc() {
			my_bool := my_group(b = false);
			my_boo*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.my_bool: bool"});
}

@(test)
ast_swizzle_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			my_array: [4] f32;
			my_array.*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"x: f32", "y: f32", "z: f32", "w: f32", "r: f32", "g: f32", "b: f32", "a: f32"});
}

@(test)
ast_swizzle_completion_one_component :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			my_array: [4] f32;
			my_array.x*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"xx: [2]f32", "xy: [2]f32", "xz: [2]f32", "xw: [2]f32"});
}

@(test)
ast_swizzle_completion_few_components :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			my_array: [2] f32;
			my_array.x*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"xx: [2]f32", "xy: [2]f32"});
}


@(test)
ast_swizzle_resolve_one_components :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			my_array: [4]f32;
			my_swizzle := my_array.x;
			my_swizz*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.my_swizzle: f32"});
}

@(test)
ast_swizzle_resolve_two_components :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		main :: proc() {
			my_array: [4]f32;
			my_swizzle := my_array.xx;
			my_swizz*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, "", {"test.my_swizzle: [2]f32"});
}

@(test)
ast_swizzle_resolve_one_component_struct_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		My_Struct :: struct {
			one: int,
			two: int,
		};
		main :: proc() {
			my_array: [4] My_Struct;
			my_array.x.*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.one: int", "My_Struct.two: int"});
}

@(test)
ast_for_in_identifier_completion :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test	
		My_Struct :: struct {
			one: int,
			two: int,
		};
		
		main :: proc() {
		
			my_array: [4]My_Struct;
		
		
			for my_element in my_array {
				my_elem*
			}
		
		}
		`,
	packages = {},
	};


	test.expect_completion_details(t, &source, "", {"test.my_element: My_Struct"});
}

@(test)
ast_completion_poly_struct_proc :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test	
		RenderPass :: struct(type : typeid) { list : ^int, data : type, }

		LightingAccumPass2 :: struct {
			foo: int,
		}		
		
		execute_lighting_pass2 :: proc(pass : RenderPass(LightingAccumPass2)) {
			pass.*
		}
		`,
	packages = {},
	};

	test.expect_completion_details(t, &source, "", {"RenderPass.list: ^int"});
}

/*
@(test)
ast_completion_context_temp :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test	

		main :: proc() {
			context.*
		}
		`,
	packages = {},
	};

	test.expect_completion_details(t, &source, "", {""});
}
*/

@(test)
ast_generic_make_completion :: proc(t: ^testing.T) {

	source := test.Source {
		main = `package test

		make :: proc{
			make_dynamic_array,
			make_dynamic_array_len,
			make_dynamic_array_len_cap,
			make_map,
			make_slice,
		};
		make_slice :: proc($T: typeid/[]$E, auto_cast len: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}
		make_map :: proc($T: typeid/map[$K]$E, auto_cast cap: int = DEFAULT_RESERVE_CAPACITY, loc := #caller_location) -> T {
		}
		make_dynamic_array :: proc($T: typeid/[dynamic]$E, loc := #caller_location) -> (T, Allocator_Error) #optional_second {		
		}
		make_dynamic_array_len :: proc($T: typeid/[dynamic]$E, auto_cast len: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}
		make_dynamic_array_len_cap :: proc($T: typeid/[dynamic]$E, auto_cast len: int, auto_cast cap: int, loc := #caller_location) -> (T, Allocator_Error) #optional_second {
		}

		My_Struct :: struct {
			my_int: int,
		}

		main :: proc() {
			allocator: Allocator;
			my_array := make([dynamic]My_Struct, 343);
			my_array[2].*
		}
		`,
		packages = {},
	};

	test.expect_completion_details(t, &source, ".", {"My_Struct.my_int: int"});
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
					w.*
				}
			}
		}
		`,
	};

	test.expect_completion_details(t, &source, ".", {"Window.height: int"});
}

/*	
	Looks like a bug in for each on w.*

	

	window_proc :: proc "std" (window: win32.Hwnd, message: u32, w_param: win32.Wparam, l_param: win32.Lparam) -> win32.Lresult {

		result: win32.Lresult;

		context = runtime.default_context();

		switch (message) {
		case win32.WM_DESTROY:
			win32.post_quit_message(0);
		case win32.WM_SIZE:
			width := bits.bitfield_extract_int(cast(int)l_param, 0, 16);
			height := bits.bitfield_extract_int(cast(int)l_param, 16, 16);
			
			for w in platform_context.windows {
				
			}

		case:
			result = win32.def_window_proc_a(window, message, w_param, l_param);
		}

		return result;
	}
*/

/*
	Figure out whether i want to introduce the runtime to the tests


*/

/*

	SymbolUntypedValue :: struct {
		type: enum {Integer, Float, String, Bool},
	}

	Can't complete nested enums(maybe structs also?)

*/

/*

	CodeLensOptions :: str*(no keyword completion) {

		resolveProvider?: boolean;
	}

*/

/*
	position_context.last_token = tokenizer.Token {
			kind = .Comma,
		};

	It shows the type instead of the label Token_Kind
*/