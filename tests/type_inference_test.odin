package tests

import "core:log"
import "core:testing"

import test "src:testing"
import "src:server"

// ============================================================================
// Type String Utility Tests
// ============================================================================

@(test)
type_inference_is_fixed_array :: proc(t: ^testing.T) {
	// Test fixed arrays
	testing.expect(t, server.is_fixed_array_type("[3]int"), "[3]int should be a fixed array")
	testing.expect(t, server.is_fixed_array_type("[10]f32"), "[10]f32 should be a fixed array")
	testing.expect(t, server.is_fixed_array_type("[?]int"), "[?]int should be a fixed array")

	// Test non-fixed arrays
	testing.expect(t, !server.is_fixed_array_type("[]int"), "[]int should not be a fixed array")
	testing.expect(t, !server.is_fixed_array_type("[dynamic]int"), "[dynamic]int should not be a fixed array")
	testing.expect(t, !server.is_fixed_array_type("[^]int"), "[^]int should not be a fixed array")
	testing.expect(t, !server.is_fixed_array_type("int"), "int should not be a fixed array")
	testing.expect(t, !server.is_fixed_array_type(""), "empty string should not be a fixed array")
}

@(test)
type_inference_is_slice_type :: proc(t: ^testing.T) {
	testing.expect(t, server.is_slice_type("[]int"), "[]int should be a slice")
	testing.expect(t, server.is_slice_type("[]string"), "[]string should be a slice")
	testing.expect(t, !server.is_slice_type("[3]int"), "[3]int should not be a slice")
	testing.expect(t, !server.is_slice_type("[dynamic]int"), "[dynamic]int should not be a slice")
	testing.expect(t, !server.is_slice_type("int"), "int should not be a slice")
}

@(test)
type_inference_is_dynamic_array :: proc(t: ^testing.T) {
	testing.expect(t, server.is_dynamic_array_type("[dynamic]int"), "[dynamic]int should be a dynamic array")
	testing.expect(t, server.is_dynamic_array_type("[dynamic]string"), "[dynamic]string should be a dynamic array")
	testing.expect(t, !server.is_dynamic_array_type("[]int"), "[]int should not be a dynamic array")
	testing.expect(t, !server.is_dynamic_array_type("[3]int"), "[3]int should not be a dynamic array")
}

@(test)
type_inference_is_map_type :: proc(t: ^testing.T) {
	testing.expect(t, server.is_map_type("map[string]int"), "map[string]int should be a map")
	testing.expect(t, server.is_map_type("map[int]string"), "map[int]string should be a map")
	testing.expect(t, !server.is_map_type("[]int"), "[]int should not be a map")
	testing.expect(t, !server.is_map_type("int"), "int should not be a map")
}

@(test)
type_inference_is_pointer_type_str :: proc(t: ^testing.T) {
	testing.expect(t, server.is_pointer_type_str("^int"), "^int should be a pointer")
	testing.expect(t, server.is_pointer_type_str("^string"), "^string should be a pointer")
	testing.expect(t, !server.is_pointer_type_str("int"), "int should not be a pointer")
	testing.expect(t, !server.is_pointer_type_str("[^]int"), "[^]int should not be a single pointer")
}

@(test)
type_inference_is_multi_pointer :: proc(t: ^testing.T) {
	testing.expect(t, server.is_multi_pointer_type("[^]int"), "[^]int should be a multi-pointer")
	testing.expect(t, server.is_multi_pointer_type("[^]u8"), "[^]u8 should be a multi-pointer")
	testing.expect(t, !server.is_multi_pointer_type("^int"), "^int should not be a multi-pointer")
	testing.expect(t, !server.is_multi_pointer_type("[]int"), "[]int should not be a multi-pointer")
}

@(test)
type_inference_is_numeric_type :: proc(t: ^testing.T) {
	// Integer types
	testing.expect(t, server.is_numeric_type("int"), "int should be numeric")
	testing.expect(t, server.is_numeric_type("i32"), "i32 should be numeric")
	testing.expect(t, server.is_numeric_type("u64"), "u64 should be numeric")
	testing.expect(t, server.is_numeric_type("uintptr"), "uintptr should be numeric")

	// Float types
	testing.expect(t, server.is_numeric_type("f32"), "f32 should be numeric")
	testing.expect(t, server.is_numeric_type("f64"), "f64 should be numeric")

	// Complex types
	testing.expect(t, server.is_numeric_type("complex64"), "complex64 should be numeric")

	// Non-numeric types
	testing.expect(t, !server.is_numeric_type("string"), "string should not be numeric")
	testing.expect(t, !server.is_numeric_type("bool"), "bool should not be numeric")
	testing.expect(t, !server.is_numeric_type("rune"), "rune should not be numeric")
}

@(test)
type_inference_is_integer_type :: proc(t: ^testing.T) {
	testing.expect(t, server.is_integer_type("int"), "int should be an integer")
	testing.expect(t, server.is_integer_type("i8"), "i8 should be an integer")
	testing.expect(t, server.is_integer_type("u128"), "u128 should be an integer")
	testing.expect(t, !server.is_integer_type("f32"), "f32 should not be an integer")
	testing.expect(t, !server.is_integer_type("bool"), "bool should not be an integer")
}

@(test)
type_inference_is_float_type :: proc(t: ^testing.T) {
	testing.expect(t, server.is_float_type("f16"), "f16 should be a float")
	testing.expect(t, server.is_float_type("f32"), "f32 should be a float")
	testing.expect(t, server.is_float_type("f64"), "f64 should be a float")
	testing.expect(t, !server.is_float_type("int"), "int should not be a float")
	testing.expect(t, !server.is_float_type("complex64"), "complex64 should not be a float")
}

@(test)
type_inference_is_boolean_type :: proc(t: ^testing.T) {
	testing.expect(t, server.is_boolean_type("bool"), "bool should be a boolean")
	testing.expect(t, server.is_boolean_type("b8"), "b8 should be a boolean")
	testing.expect(t, server.is_boolean_type("b32"), "b32 should be a boolean")
	testing.expect(t, !server.is_boolean_type("int"), "int should not be a boolean")
	testing.expect(t, !server.is_boolean_type("string"), "string should not be a boolean")
}

@(test)
type_inference_is_string_type :: proc(t: ^testing.T) {
	testing.expect(t, server.is_string_type("string"), "string should be a string type")
	testing.expect(t, server.is_string_type("cstring"), "cstring should be a string type")
	testing.expect(t, !server.is_string_type("[]u8"), "[]u8 should not be a string type")
	testing.expect(t, !server.is_string_type("int"), "int should not be a string type")
}

// ============================================================================
// Type Extraction Tests
// ============================================================================

@(test)
type_inference_extract_element_type :: proc(t: ^testing.T) {
	// Array types
	testing.expect_value(t, server.extract_element_type("[3]int"), "int")
	testing.expect_value(t, server.extract_element_type("[10]f32"), "f32")

	// Slice types
	testing.expect_value(t, server.extract_element_type("[]int"), "int")
	testing.expect_value(t, server.extract_element_type("[]string"), "string")

	// Dynamic array types
	testing.expect_value(t, server.extract_element_type("[dynamic]int"), "int")

	// Map types (returns value type)
	testing.expect_value(t, server.extract_element_type("map[string]int"), "int")
	testing.expect_value(t, server.extract_element_type("map[int]string"), "string")

	// Nested map
	testing.expect_value(t, server.extract_element_type("map[string]map[int]f32"), "map[int]f32")

	// Empty/invalid
	testing.expect_value(t, server.extract_element_type(""), "")
	testing.expect_value(t, server.extract_element_type("int"), "")
}

@(test)
type_inference_extract_map_key_type :: proc(t: ^testing.T) {
	testing.expect_value(t, server.extract_map_key_type("map[string]int"), "string")
	testing.expect_value(t, server.extract_map_key_type("map[int]string"), "int")
	testing.expect_value(t, server.extract_map_key_type("map[MyKey]MyValue"), "MyKey")

	// Invalid inputs
	testing.expect_value(t, server.extract_map_key_type(""), "")
	testing.expect_value(t, server.extract_map_key_type("[]int"), "")
	testing.expect_value(t, server.extract_map_key_type("int"), "")
}

@(test)
type_inference_extract_pointee_type :: proc(t: ^testing.T) {
	testing.expect_value(t, server.extract_pointee_type("^int"), "int")
	testing.expect_value(t, server.extract_pointee_type("^string"), "string")
	testing.expect_value(t, server.extract_pointee_type("^MyStruct"), "MyStruct")

	// Multi-pointer
	testing.expect_value(t, server.extract_pointee_type("[^]int"), "int")
	testing.expect_value(t, server.extract_pointee_type("[^]u8"), "u8")

	// Invalid inputs
	testing.expect_value(t, server.extract_pointee_type("int"), "")
	testing.expect_value(t, server.extract_pointee_type("[]int"), "")
}

@(test)
type_inference_extract_array_size :: proc(t: ^testing.T) {
	testing.expect_value(t, server.extract_array_size("[3]int"), "3")
	testing.expect_value(t, server.extract_array_size("[100]f32"), "100")
	testing.expect_value(t, server.extract_array_size("[N]int"), "N")
	testing.expect_value(t, server.extract_array_size("[?]int"), "?")

	// Non-fixed arrays
	testing.expect_value(t, server.extract_array_size("[]int"), "")
	testing.expect_value(t, server.extract_array_size("[dynamic]int"), "")
	testing.expect_value(t, server.extract_array_size("[^]int"), "")
}

// ============================================================================
// Type Construction Tests
// ============================================================================

@(test)
type_inference_make_pointer_type :: proc(t: ^testing.T) {
	testing.expect_value(t, server.make_pointer_type("int"), "^int")
	testing.expect_value(t, server.make_pointer_type("string"), "^string")
	testing.expect_value(t, server.make_pointer_type(""), "")
}

@(test)
type_inference_make_slice_type :: proc(t: ^testing.T) {
	testing.expect_value(t, server.make_slice_type("int"), "[]int")
	testing.expect_value(t, server.make_slice_type("string"), "[]string")
	testing.expect_value(t, server.make_slice_type(""), "")
}

@(test)
type_inference_make_dynamic_array_type :: proc(t: ^testing.T) {
	testing.expect_value(t, server.make_dynamic_array_type("int"), "[dynamic]int")
	testing.expect_value(t, server.make_dynamic_array_type("string"), "[dynamic]string")
	testing.expect_value(t, server.make_dynamic_array_type(""), "")
}

// ============================================================================
// Type Compatibility Tests
// ============================================================================

@(test)
type_inference_types_are_compatible :: proc(t: ^testing.T) {
	// Same types are compatible
	testing.expect(t, server.types_are_compatible("int", "int"), "int should be compatible with int")
	testing.expect(t, server.types_are_compatible("string", "string"), "string should be compatible with string")

	// Empty types are compatible with anything
	testing.expect(t, server.types_are_compatible("", "int"), "empty should be compatible with int")
	testing.expect(t, server.types_are_compatible("int", ""), "int should be compatible with empty")

	// Any accepts anything
	testing.expect(t, server.types_are_compatible("int", "any"), "int should be compatible with any")
	testing.expect(t, server.types_are_compatible("string", "any"), "string should be compatible with any")

	// rawptr accepts pointers
	testing.expect(t, server.types_are_compatible("^int", "rawptr"), "^int should be compatible with rawptr")
	testing.expect(t, server.types_are_compatible("[^]int", "rawptr"), "[^]int should be compatible with rawptr")

	// Different types are not compatible
	testing.expect(t, !server.types_are_compatible("int", "string"), "int should not be compatible with string")
}

@(test)
type_inference_get_common_type :: proc(t: ^testing.T) {
	// Same types
	testing.expect_value(t, server.get_common_type("int", "int"), "int")

	// Empty types
	testing.expect_value(t, server.get_common_type("", "int"), "int")
	testing.expect_value(t, server.get_common_type("int", ""), "int")

	// Float wins over integer
	testing.expect_value(t, server.get_common_type("int", "f32"), "f32")
	testing.expect_value(t, server.get_common_type("f64", "i32"), "f64")
}

// ============================================================================
// Iteration Type Inference Tests
// ============================================================================

@(test)
type_inference_get_iteration_types :: proc(t: ^testing.T) {
	// String iteration: for char, index in str
	first, second := server.get_iteration_types("string")
	testing.expect_value(t, first, "rune")
	testing.expect_value(t, second, "int")

	// Slice iteration: for elem, index in slice
	first, second = server.get_iteration_types("[]int")
	testing.expect_value(t, first, "int")
	testing.expect_value(t, second, "int")

	// Array iteration
	first, second = server.get_iteration_types("[10]f32")
	testing.expect_value(t, first, "f32")
	testing.expect_value(t, second, "int")

	// Map iteration: for key, value in map
	first, second = server.get_iteration_types("map[string]int")
	testing.expect_value(t, first, "string")
	testing.expect_value(t, second, "int")

	// Empty container
	first, second = server.get_iteration_types("")
	testing.expect_value(t, first, "")
	testing.expect_value(t, second, "")
}

// ============================================================================
// Inference_Context Tests
// ============================================================================

@(test)
type_inference_context_variable_registration :: proc(t: ^testing.T) {
	ctx := server.make_inference_context(nil, nil)
	defer server.destroy_inference_context(&ctx)

	// Register some variables
	server.register_variable_type(&ctx, "x", "int")
	server.register_variable_type(&ctx, "y", "string")

	// Verify retrieval
	x_type, x_ok := server.get_variable_type(&ctx, "x")
	testing.expect(t, x_ok, "x should be found")
	testing.expect_value(t, x_type, "int")

	y_type, y_ok := server.get_variable_type(&ctx, "y")
	testing.expect(t, y_ok, "y should be found")
	testing.expect_value(t, y_type, "string")

	// Non-existent variable
	_, z_ok := server.get_variable_type(&ctx, "z")
	testing.expect(t, !z_ok, "z should not be found")
}

// ============================================================================
// Extract Proc Integration Tests (ensuring type inference still works)
// ============================================================================

@(test)
type_inference_extract_proc_with_typed_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x: int = 1
	{<}y := x + 2{>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		"Extract Proc",
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	y := x + 2
	return y
}`,
	)
}

@(test)
type_inference_extract_proc_with_float :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := 1.0
	{<}y := x + 2.0{>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		"Extract Proc",
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: f64) -> f64 {
	y := x + 2.0
	return y
}`,
	)
}

@(test)
type_inference_extract_proc_with_string :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := "hello"
	{<}y := x{>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		"Extract Proc",
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: string) -> string {
	y := x
	return y
}`,
	)
}

@(test)
type_inference_extract_proc_with_boolean_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := 1
	{<}y := x > 0{>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		"Extract Proc",
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> bool {
	y := x > 0
	return y
}`,
	)
}

@(test)
type_inference_extract_proc_with_len :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	arr := []int{1, 2, 3}
	{<}n := len(arr){>}
	x := n
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		"Extract Proc",
		"n := extracted_proc(arr)",
		`

extracted_proc :: proc(arr: []int) -> int {
	n := len(arr)
	return n
}`,
	)
}

@(test)
type_inference_extract_proc_with_type_cast :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := 42
	{<}y := f32(x){>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		"Extract Proc",
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> f32 {
	y := f32(x)
	return y
}`,
	)
}
