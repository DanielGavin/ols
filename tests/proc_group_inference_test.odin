package tests

// Procedure group overload resolution tests,
// mirroring the Odin compiler tests from:
// tests/internal/test_proc_group_type_inference.odin

import "core:testing"
import "src:common"
import test "src:testing"

// Declarations in the embedded sources start at column 0 on purpose
// so expected locations are trivial: character = 0, end = len(name)
@(private = "file")
overload_location :: proc(line: int, name: string) -> common.Location {
	return {range = {{line, 0}, {line, len(name)}}}
}

@(test)
test_proc_group_default_arg_precedence_zero_args :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
My_Bit_Set :: bit_set[enum{A, B, C}]
proc_one_default :: proc(a: My_Bit_Set={.A}) -> int { return 1 }
proc_two_defaults :: proc(a: My_Bit_Set={.B}, b: My_Bit_Set={.C}) -> int { return 2 }
group :: proc{proc_one_default, proc_two_defaults}

main :: proc() {
	grou{*}p()
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_one_default")})
}

@(test)
test_proc_group_default_arg_precedence_typed_bitset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
My_Bit_Set :: bit_set[enum{A, B, C}]
proc_one_default :: proc(a: My_Bit_Set={.A}) -> int { return 1 }
proc_two_defaults :: proc(a: My_Bit_Set={.B}, b: My_Bit_Set={.C}) -> int { return 2 }
group :: proc{proc_one_default, proc_two_defaults}

main :: proc() {
	grou{*}p(My_Bit_Set{.A})
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_one_default")})
}

@(test)
test_proc_group_default_arg_precedence_untyped_bitset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
My_Bit_Set :: bit_set[enum{A, B, C}]
proc_one_default :: proc(a: My_Bit_Set={.A}) -> int { return 1 }
proc_two_defaults :: proc(a: My_Bit_Set={.B}, b: My_Bit_Set={.C}) -> int { return 2 }
group :: proc{proc_one_default, proc_two_defaults}

main :: proc() {
	grou{*}p({.A})
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_one_default")})
}

@(test)
test_proc_group_default_arg_precedence_two_args :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
My_Bit_Set :: bit_set[enum{A, B, C}]
proc_one_default :: proc(a: My_Bit_Set={.A}) -> int { return 1 }
proc_two_defaults :: proc(a: My_Bit_Set={.B}, b: My_Bit_Set={.C}) -> int { return 2 }
group :: proc{proc_one_default, proc_two_defaults}

main :: proc() {
	grou{*}p({.B}, {.C})
}
`,
		config = {enable_overload_resolution = true},
	}

	// only proc_two_defaults takes two arguments
	test.expect_definition_locations(t, &source, {overload_location(3, "proc_two_defaults")})
}

@(test)
test_proc_group_default_arg_precedence_zero_args_reversed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
My_Bit_Set :: bit_set[enum{A, B, C}]
proc_one_default :: proc(a: My_Bit_Set={.A}) -> int { return 1 }
proc_two_defaults :: proc(a: My_Bit_Set={.B}, b: My_Bit_Set={.C}) -> int { return 2 }
group :: proc{proc_two_defaults, proc_one_default}

main :: proc() {
	grou{*}p()
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_one_default")})
}

@(test)
test_proc_group_default_arg_precedence_exact_vs_defaulted :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_exact :: proc(x: int) -> int { return 1 }
proc_defaulted :: proc(x: int, y := 0) -> int { return 2 }
group :: proc{proc_exact, proc_defaulted}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_exact")})
}

@(test)
test_proc_group_default_arg_precedence_fewer_defaults :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_fewer :: proc(x: int, y := 0) -> int { return 1 }
proc_more :: proc(x: int, y := 0, z := 0) -> int { return 2 }
group :: proc{proc_fewer, proc_more}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_fewer")})
}

@(test)
test_proc_group_default_arg_precedence_fewer_defaults_reversed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_fewer :: proc(x: int, y := 0) -> int { return 1 }
proc_more :: proc(x: int, y := 0, z := 0) -> int { return 2 }
group :: proc{proc_more, proc_fewer}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_fewer")})
}

@(test)
test_proc_group_arity_precedence_non_variadic :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_exact :: proc(x: int) -> int { return 1 }
proc_variadic :: proc(x: int, r: ..int) -> int { return 2 }
group :: proc{proc_exact, proc_variadic}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_exact")})
}

@(test)
test_proc_group_arity_precedence_variadic :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_exact :: proc(x: int) -> int { return 1 }
proc_variadic :: proc(x: int, r: ..int) -> int { return 2 }
group :: proc{proc_exact, proc_variadic}

main :: proc() {
	grou{*}p(1, 2, 3)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_variadic")})
}

@(test)
test_proc_group_arity_precedence_defaulted_sibling :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_int :: proc(x: int) -> int { return 1 }
proc_string :: proc(x: string) -> int { return 2 }
proc_f32 :: proc(x: f32) -> int { return 3 }
proc_f32_defaulted :: proc(x: f32, y: int = 0) -> int { return 4 }
proc_rune :: proc(x: rune) -> int { return 5 }
group :: proc{proc_int, proc_string, proc_f32, proc_f32_defaulted, proc_rune}

main :: proc() {
	v: f32
	grou{*}p(v)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(3, "proc_f32")})
}

@(test)
test_proc_group_untyped_constant_default_type_int_vs_i64 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_int :: proc(x: int) -> int { return 1 }
proc_i64 :: proc(x: i64) -> int { return 2 }
group :: proc{proc_int, proc_i64}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_int")})
}

@(test)
test_proc_group_untyped_constant_default_type_int_vs_i64_reversed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_int :: proc(x: int) -> int { return 1 }
proc_i64 :: proc(x: i64) -> int { return 2 }
group :: proc{proc_i64, proc_int}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_int")})
}

@(test)
test_proc_group_untyped_constant_default_type_int_i64_vs_f64 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_i64 :: proc(x: i64) -> int { return 1 }
proc_f64 :: proc(x: f64) -> int { return 2 }
group :: proc{proc_i64, proc_f64}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_i64")})
}

@(test)
test_proc_group_untyped_constant_default_type_float_f32_vs_f64 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_f32 :: proc(x: f32) -> int { return 1 }
proc_f64 :: proc(x: f64) -> int { return 2 }
group :: proc{proc_f32, proc_f64}

main :: proc() {
	grou{*}p(1.5)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_f64")})
}

@(test)
test_proc_group_untyped_constant_default_type_rune_vs_int :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_rune :: proc(x: rune) -> int { return 1 }
proc_int :: proc(x: int) -> int { return 2 }
group :: proc{proc_rune, proc_int}

main :: proc() {
	grou{*}p('x')
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_rune")})
}

@(test)
test_proc_group_untyped_constant_default_type_rune_vs_int_reversed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_rune :: proc(x: rune) -> int { return 1 }
proc_int :: proc(x: int) -> int { return 2 }
group :: proc{proc_int, proc_rune}

main :: proc() {
	grou{*}p('x')
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_rune")})
}

@(test)
test_proc_group_untyped_constant_default_type_string_vs_cstring :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_string :: proc(x: string) -> int { return 1 }
proc_cstring :: proc(x: cstring) -> int { return 2 }
group :: proc{proc_string, proc_cstring}

main :: proc() {
	grou{*}p("hi")
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_string")})
}

@(test)
test_proc_group_untyped_constant_default_type_string_vs_cstring_reversed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_string :: proc(x: string) -> int { return 1 }
proc_cstring :: proc(x: cstring) -> int { return 2 }
group :: proc{proc_cstring, proc_string}

main :: proc() {
	grou{*}p("hi")
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_string")})
}

@(test)
test_proc_group_untyped_constant_default_type_bool_vs_b32 :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_bool :: proc(x: bool) -> int { return 1 }
proc_b32 :: proc(x: b32) -> int { return 2 }
group :: proc{proc_bool, proc_b32}

main :: proc() {
	grou{*}p(true)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_bool")})
}

@(test)
test_proc_group_untyped_constant_default_type_bool_vs_b32_reversed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_bool :: proc(x: bool) -> int { return 1 }
proc_b32 :: proc(x: b32) -> int { return 2 }
group :: proc{proc_b32, proc_bool}

main :: proc() {
	grou{*}p(true)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_bool")})
}

@(test)
test_proc_group_untyped_constant_default_type_int_u8_vs_i64_overflow :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_u8 :: proc(x: u8) -> int { return 1 }
proc_i64 :: proc(x: i64) -> int { return 2 }
group :: proc{proc_u8, proc_i64}

main :: proc() {
	grou{*}p(100000)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_i64")})
}

@(test)
test_proc_group_polymorphic_precedence_concrete_vs_generic :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_concrete :: proc(x: int) -> int { return 1 }
proc_generic :: proc(x: $T) -> int { return 2 }
group :: proc{proc_concrete, proc_generic}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_concrete")})
}

@(test)
test_proc_group_polymorphic_precedence_concrete_vs_generic_typed_arg :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_concrete :: proc(x: int) -> int { return 1 }
proc_generic :: proc(x: $T) -> int { return 2 }
group :: proc{proc_concrete, proc_generic}

main :: proc() {
	v: int = 1
	grou{*}p(v)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_concrete")})
}

@(test)
test_proc_group_polymorphic_precedence_generic_only_viable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_concrete :: proc(x: string) -> int { return 1 }
proc_generic :: proc(x: $T) -> int { return 2 }
group :: proc{proc_concrete, proc_generic}

main :: proc() {
	grou{*}p(1)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_generic")})
}

@(test)
test_proc_group_polymorphic_precedence_value_poly_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_static :: proc($S: string) -> int { return 1 }
proc_dynamic :: proc(s: string) -> int { return 2 }
group :: proc{proc_static, proc_dynamic}

main :: proc() {
	grou{*}p("literal")
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_static")})
}

@(test)
test_proc_group_polymorphic_precedence_value_poly_runtime_value :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_static :: proc($S: string) -> int { return 1 }
proc_dynamic :: proc(s: string) -> int { return 2 }
group :: proc{proc_static, proc_dynamic}

main :: proc() {
	s := "runtime"
	grou{*}p(s)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_dynamic")})
}

@(test)
test_proc_group_polymorphic_precedence_three_tiers :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_generic :: proc(x: $T) -> int { return 3 }
proc_concrete :: proc(s: string) -> int { return 2 }
proc_static :: proc($S: string) -> int { return 1 }
group :: proc{proc_generic, proc_concrete, proc_static}

main :: proc() {
	grou{*}p("literal")
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(3, "proc_static")})
}

@(test)
test_proc_group_polymorphic_precedence_specialized_vs_generic :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_slice :: proc(x: $T/[]$E) -> int { return 1 }
proc_generic :: proc(x: $T) -> int { return 2 }
group :: proc{proc_slice, proc_generic}

main :: proc() {
	s := []int{1}
	grou{*}p(s)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_slice")})
}

@(test)
test_proc_group_polymorphic_precedence_specialized_vs_generic_reversed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_slice :: proc(x: $T/[]$E) -> int { return 1 }
proc_generic :: proc(x: $T) -> int { return 2 }
group :: proc{proc_generic, proc_slice}

main :: proc() {
	s := []int{1}
	grou{*}p(s)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(1, "proc_slice")})
}

@(test)
test_proc_group_polymorphic_precedence_proc_typed_param :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
f_poly :: proc(x: $T) -> T { return x }
foo_concrete :: proc(x: int, g: proc(int) -> int) -> int { return 1 }
foo_impossible :: proc(x: int, g: proc(int, int) -> string) -> int { return 2 }
group :: proc{foo_concrete, foo_impossible}

main :: proc() {
	grou{*}p(1, f_poly)
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "foo_concrete")})
}

@(test)
test_proc_group_type_inference_literals_for_various_parameters :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
Bit_Set :: bit_set[enum{A, B, C}]
proc_0 :: proc() -> int { return 0 }
proc_1 :: proc(Bit_Set) -> int { return 1 }
proc_2 :: proc(int, Bit_Set) -> int { return 2 }
proc_3 :: proc(f32, Bit_Set) -> int { return 3 }
group :: proc{proc_0, proc_1, proc_2, proc_3}

main :: proc() {
	grou{*}p(9, {.A})
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(4, "proc_2")})
}

@(test)
test_proc_group_type_inference_literals_with_default_args :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
Bit_Set :: bit_set[enum{A, B, C}]
proc_nil :: proc() {}
proc_default_arg :: proc(a: Bit_Set = {.A}) -> Bit_Set { return a }
group :: proc{proc_nil, proc_default_arg}

main :: proc() {
	grou{*}p({.A})
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(3, "proc_default_arg")})
}

@(test)
test_proc_group_type_inference_literals_for_various_types :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
proc_nil :: proc() {}
proc_array :: proc(a: [3]f32) -> [3]f32 { return a }
group_array :: proc{proc_nil, proc_array}

main :: proc() {
	grou{*}p_array({1.1, 2.2, 3.3})
}
`,
		config = {enable_overload_resolution = true},
	}

	test.expect_definition_locations(t, &source, {overload_location(2, "proc_array")})
}
