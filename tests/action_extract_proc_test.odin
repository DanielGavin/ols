package tests

import "core:testing"

import test "src:testing"

EXTRACT_PROC_ACTION :: "Extract Proc"

@(test)
action_extract_proc_simple_statement :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 1
	{<}y := x + 2{>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	y := x + 2
	return y
}`,
	)
}

@(test)
action_extract_proc_multiple_statements :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 1
	{<}y := x + 2
	z := y * 3{>}
	w := z
}
`,
		packages = {},
	}

	// Only z is used after selection, y is used only within selection
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"z := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	y := x + 2
	z := y * 3
	return z
}`,
	)
}

@(test)
action_extract_proc_no_params_no_returns :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	{<}x := 1
	y := 2{>}
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc()",
		`

extracted_proc :: proc() {
	x := 1
	y := 2
}`,
	)
}

@(test)
action_extract_proc_with_modification :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 1
	{<}x = x + 1{>}
	y := x
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&x)",
		`

extracted_proc :: proc(x: ^int) {
	x^ = x^ + 1
}`,
	)
}

@(test)
action_extract_proc_with_pointer_param :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x: ^int = nil
	{<}x^ = 5{>}
	y := x^
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(x)",
		`

extracted_proc :: proc(x: ^int) {
	x^ = 5
}`,
	)
}

@(test)
action_extract_proc_with_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

Point :: struct { x, y: int }

main :: proc() {
	p := Point{1, 2}
	{<}p.x = 10{>}
	z := p.x
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&p)",
		`

extracted_proc :: proc(p: ^Point) {
	p.x = 10
}`,
	)
}

@(test)
action_extract_proc_with_array_index :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	arr := [3]int{1, 2, 3}
	{<}arr[0] = 10{>}
	x := arr[0]
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&arr)",
		`

extracted_proc :: proc(arr: ^[3]int) {
	arr[0] = 10
}`,
	)
}

@(test)
action_extract_proc_with_proc_param :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

process :: proc(n: int) {
	{<}result := n * 2{>}
	x := result
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"result := extracted_proc(n)",
		`

extracted_proc :: proc(n: int) -> int {
	result := n * 2
	return result
}`,
	)
}

@(test)
action_extract_proc_with_if_statement :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}if x > 0 {
		x = x - 1
	}{>}
	y := x
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&x)",
		`

extracted_proc :: proc(x: ^int) {
	if x^ > 0 {
		x^ = x^ - 1
	}
}`,
	)
}

@(test)
action_extract_proc_with_for_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	sum := 0
	{<}for i := 0; i < 10; i += 1 {
		sum += i
	}{>}
	result := sum
}
`,
		packages = {},
	}

	// Loop variable i is declared within the for statement and is loop-scoped
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&sum)",
		`

extracted_proc :: proc(sum: ^int) {
	for i := 0; i < 10; i += 1 {
		sum^ += i
	}
}`,
	)
}

@(test)
action_extract_proc_with_range_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	arr := [3]int{1, 2, 3}
	sum := 0
	{<}for val in arr {
		sum += val
	}{>}
	result := sum
}
`,
		packages = {},
	}

	// Range loop variable val is detected as a read
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&arr, &sum)",
		`

extracted_proc :: proc(arr: ^[3]int, sum: ^int) {
	for val in arr {
		sum^ += val
	}
}`,
	)
}

@(test)
action_extract_proc_with_call_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

helper :: proc(n: int) -> f32 { return n * 2 }

main :: proc() {
	x := 5
	{<}y := helper(x){>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> f32 {
	y := helper(x)
	return y
}`,
	)
}

@(test)
action_extract_proc_with_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 1
	b := 2
	{<}c := a + b * 2{>}
	d := c
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"c := extracted_proc(a, b)",
		`

extracted_proc :: proc(a: int, b: int) -> int {
	c := a + b * 2
	return c
}`,
	)
}

@(test)
action_extract_proc_with_ternary :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}y := x > 0 ? 1 : 0{>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	y := x > 0 ? 1 : 0
	return y
}`,
	)
}

@(test)
action_extract_proc_with_compound_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

Point :: struct { x, y: int }

main :: proc() {
	a := 1
	b := 2
	{<}p := Point{x = a, y = b}{>}
	z := p.x
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"p := extracted_proc(a, b)",
		`

extracted_proc :: proc(a: int, b: int) -> Point {
	p := Point{x = a, y = b}
	return p
}`,
	)
}

@(test)
action_extract_proc_nested_selector :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

Inner :: struct { value: int }
Outer :: struct { inner: Inner }

main :: proc() {
	o := Outer{inner = Inner{value = 5}}
	{<}o.inner.value = 10{>}
	x := o.inner.value
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&o)",
		`

extracted_proc :: proc(o: ^Outer) {
	o.inner.value = 10
}`,
	)
}

@(test)
action_extract_proc_multiple_vars_used_after :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	input := 10
	{<}a := input + 1
	b := input + 2
	c := a + b{>}
	x := a
	y := b
	z := c
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"a, b, c := extracted_proc(input)",
		`

extracted_proc :: proc(input: int) -> (int, int, int) {
	a := input + 1
	b := input + 2
	c := a + b
	return a, b, c
}`,
	)
}

@(test)
action_extract_proc_with_len :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	arr := [3]int{1, 2, 3}
	{<}n := len(arr){>}
	x := n
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"n := extracted_proc(&arr)",
		`

extracted_proc :: proc(arr: ^[3]int) -> int {
	n := len(arr)
	return n
}`,
	)
}

@(test)
action_extract_proc_with_make :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	size := 10
	{<}arr := make([dynamic]int, size){>}
	x := arr[0]
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"arr := extracted_proc(size)",
		`

extracted_proc :: proc(size: int) -> [dynamic]int {
	arr := make([dynamic]int, size)
	return arr
}`,
	)
}

@(test)
action_extract_proc_not_available_for_defer :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	{<}defer free(nil){>}
}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_not_available_for_nested_defer :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	{<}if true {
		defer free(nil)
	}{>}
}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_not_available_outside_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

{<}CONSTANT :: 42{>}

main :: proc() {}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_not_available_for_empty_selection :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 1{*}
}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_with_switch :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	val := 1
	{<}result := 0
	switch val {
	case 1:
		result = 10
	case 2:
		result = 20
	}{>}
	x := result
}
`,
		packages = {},
	}

	// Switch statement doesn't analyze switch expression yet
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"result := extracted_proc()",
		`

extracted_proc :: proc() -> int {
	result := 0
	switch val {
	case 1:
		result = 10
	case 2:
		result = 20
	}
	return result
}`,
	)
}

@(test)
action_extract_proc_with_multiple_modifications :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 1
	b := 2
	{<}a = a + 1
	b = b + 1{>}
	x := a + b
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&a, &b)",
		`

extracted_proc :: proc(a: ^int, b: ^int) {
	a^ = a^ + 1
	b^ = b^ + 1
}`,
	)
}

@(test)
action_extract_proc_with_slice_operations :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	arr := [5]int{1, 2, 3, 4, 5}
	{<}slice := arr[1:3]{>}
	x := slice[0]
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"slice := extracted_proc(&arr)",
		`

extracted_proc :: proc(arr: ^[5]int) -> []int {
	slice := arr[1:3]
	return slice
}`,
	)
}

@(test)
action_extract_proc_read_only_vars :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 1
	b := 2
	{<}c := a + b{>}
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(a, b)",
		`

extracted_proc :: proc(a: int, b: int) {
	c := a + b
}`,
	)
}

@(test)
action_extract_proc_mixed_read_modify :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 1
	b := 2
	{<}a = a + b{>}
	c := a
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&a, b)",
		`

extracted_proc :: proc(a: ^int, b: int) {
	a^ = a^ + b
}`,
	)
}

@(test)
action_extract_proc_with_paren_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 1
	b := 2
	{<}c := (a + b) * 2{>}
	d := c
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"c := extracted_proc(a, b)",
		`

extracted_proc :: proc(a: int, b: int) -> int {
	c := (a + b) * 2
	return c
}`,
	)
}

@(test)
action_extract_proc_with_unary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}y := -x{>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	y := -x
	return y
}`,
	)
}

@(test)
action_extract_proc_with_addr_of :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}ptr := &x{>}
	y := ptr^
}
`,
		packages = {},
	}

	// x is read via &x, ptr is declared and used after
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"ptr := extracted_proc(&x)",
		`

extracted_proc :: proc(x: ^int) -> ^int {
	ptr := x
	return ptr
}`,
	)
}

@(test)
action_extract_proc_else_if_chain :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}result := 0
	if x > 10 {
		result = 1
	} else if x > 5 {
		result = 2
	} else {
		result = 3
	}{>}
	y := result
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"result := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	result := 0
	if x > 10 {
		result = 1
	} else if x > 5 {
		result = 2
	} else {
		result = 3
	}
	return result
}`,
	)
}

@(test)
action_extract_proc_nested_loops :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	total := 0
	{<}for i := 0; i < 3; i += 1 {
		for j := 0; j < 3; j += 1 {
			total += i * j
		}
	}{>}
	result := total
}
`,
		packages = {},
	}

	// Nested loop variables i, j are detected as reads
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&total)",
		`

extracted_proc :: proc(total: ^int) {
	for i := 0; i < 3; i += 1 {
		for j := 0; j < 3; j += 1 {
			total^ += i * j
		}
	}
}`,
	)
}

@(test)
action_extract_proc_with_assert :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}assert(x > 0){>}
	y := x
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(x)",
		`

extracted_proc :: proc(x: int) {
	assert(x > 0)
}`,
	)
}

@(test)
action_extract_proc_with_min_max :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 5
	b := 10
	{<}c := min(a, b)
	d := max(a, b){>}
	x := c + d
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"c, d := extracted_proc(a, b)",
		`

extracted_proc :: proc(a: int, b: int) -> (int, int) {
	c := min(a, b)
	d := max(a, b)
	return c, d
}`,
	)
}

@(test)
action_extract_proc_with_size_of :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	{<}n := size_of(int){>}
	x := n
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"n := extracted_proc()",
		`

extracted_proc :: proc() -> int {
	n := size_of(int)
	return n
}`,
	)
}

@(test)
action_extract_proc_var_not_used_after :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	input := 10
	{<}temp := input * 2
	result := temp + 1{>}
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(input)",
		`

extracted_proc :: proc(input: int) {
	temp := input * 2
	result := temp + 1
}`,
	)
}

@(test)
action_extract_proc_partial_vars_used_after :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	input := 10
	{<}temp := input * 2
	result := temp + 1{>}
	x := result
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"result := extracted_proc(input)",
		`

extracted_proc :: proc(input: int) -> int {
	temp := input * 2
	result := temp + 1
	return result
}`,
	)
}

@(test)
action_extract_proc_with_block_stmt :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}{
		x = x + 1
	}{>}
	y := x
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&x)",
		`

extracted_proc :: proc(x: ^int) {
	{
		x^ = x^ + 1
	}
}`,
	)
}

@(test)
action_extract_proc_string_operations :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	s := "hello"
	{<}n := len(s){>}
	x := n
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"n := extracted_proc(s)",
		`

extracted_proc :: proc(s: string) -> int {
	n := len(s)
	return n
}`,
	)
}

@(test)
action_extract_proc_with_type_cast :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}y := f32(x){>}
	z := y
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> f32 {
	y := f32(x)
	return y
}`,
	)
}

@(test)
action_extract_proc_with_append :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	arr := make([dynamic]int)
	val := 5
	{<}append(&arr, val){>}
	x := arr[0]
}
`,
		packages = {},
	}

	// &arr in source is treated as reading arr, not modifying
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(arr, val)",
		`

extracted_proc :: proc(arr: [dynamic]int, val: int) {
	append(&arr, val)
}`,
	)
}

@(test)
action_extract_proc_multiple_procs_in_file :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

helper :: proc() {}

main :: proc() {
	x := 5
	{<}y := x + 1{>}
	z := y
}

another :: proc() {}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	y := x + 1
	return y
}`,
	)
}

@(test)
action_extract_proc_at_end_of_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	{<}y := x + 1{>}
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(x)",
		`

extracted_proc :: proc(x: int) {
	y := x + 1
}`,
	)
}

@(test)
action_extract_proc_with_map_access :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	m := make(map[string]int)
	{<}val := m["key"]{>}
	x := val
}
`,
		packages = {},
	}

	// m is read via index access
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"val := extracted_proc(m)",
		`

extracted_proc :: proc(m: map[string]int) -> int {
	val := m["key"]
	return val
}`,
	)
}

@(test)
action_extract_proc_map_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	m := make(map[string]int)
	val := 5
	{<}m["key"] = val{>}
	x := m["key"]
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&m, val)",
		`

extracted_proc :: proc(m: ^map[string]int, val: int) {
	m["key"] = val
}`,
	)
}

@(test)
action_extract_proc_with_or_else :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	m := make(map[string]int)
	{<}val := m["key"] or_else 0{>}
	x := val
}
`,
		packages = {},
	}

	// or_else expression not fully analyzed yet
	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"val := extracted_proc()",
		`

extracted_proc :: proc() -> int {
	val := m["key"] or_else 0
	return val
}`,
	)
}

@(test)
action_extract_proc_no_statements_selected :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 1
{<}
{>}	y := x
}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_with_nested_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	inner := proc() {
		x := 5
		{<}y := x + 1{>}
		z := y
	}
	inner()
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"y := extracted_proc(x)",
		`

extracted_proc :: proc(x: int) -> int {
	y := x + 1
	return y
}`,
	)
}

@(test)
action_extract_proc_defer_at_selection_start :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	{<}defer cleanup()
	x := 5{>}
}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_defer_at_selection_end :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	{<}x := 5
	defer cleanup(){>}
}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_defer_in_middle :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	{<}x := 5
	defer cleanup()
	y := x + 1{>}
}
`,
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_PROC_ACTION})
}

@(test)
action_extract_proc_with_multiple_params :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 1
	b := 2
	c := 3
	{<}d := a + b + c{>}
	e := d
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"d := extracted_proc(a, b, c)",
		`

extracted_proc :: proc(a: int, b: int, c: int) -> int {
	d := a + b + c
	return d
}`,
	)
}

@(test)
action_extract_proc_only_modify_some_vars :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	a := 1
	b := 2
	c := 3
	{<}a = a + b
	c = c + b{>}
	x := a + c
}
`,
		packages = {},
	}

	test.expect_action_with_edit(
		t,
		&source,
		EXTRACT_PROC_ACTION,
		"extracted_proc(&a, b, &c)",
		`

extracted_proc :: proc(a: ^int, b: int, c: ^int) {
	a^ = a^ + b
	c^ = c^ + b
}`,
	)
}
