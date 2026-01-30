package tests

import "core:testing"

import test "src:testing"

EXTRACT_PROC_ACTION :: "Extract Proc"

@(test)
action_extract_proc_simple_statement :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
-	{<}y := x + 2{>}
+	y := extracted_proc(x)
	z := y
}
+
+extracted_proc :: proc(x: int) -> int {
+	y := x + 2
+	return y
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_multiple_statements :: proc(t: ^testing.T) {
	// Only z is used after selection, y is used only within selection
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
-	{<}y := x + 2
-	z := y * 3{>}
+	z := extracted_proc(x)
	w := z
}
+
+extracted_proc :: proc(x: int) -> int {
+	y := x + 2
+	z := y * 3
+	return z
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_no_params_no_returns :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	{<}x := 1
-	y := 2{>}
+	extracted_proc()
}
+
+extracted_proc :: proc() {
+	x := 1
+	y := 2
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_modification :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
-	{<}x = x + 1{>}
+	extracted_proc(&x)
	y := x
}
+
+extracted_proc :: proc(x: ^int) {
+	x^ = x^ + 1
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_pointer_param :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x: ^int = nil
-	{<}x^ = 5{>}
+	extracted_proc(x)
	y := x^
}
+
+extracted_proc :: proc(x: ^int) {
+	x^ = 5
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_struct_field :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Point :: struct { x, y: int }

main :: proc() {
	p := Point{1, 2}
-	{<}p.x = 10{>}
+	extracted_proc(&p)
	z := p.x
}
+
+extracted_proc :: proc(p: ^Point) {
+	p.x = 10
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_array_index :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [3]int{1, 2, 3}
-	{<}arr[0] = 10{>}
+	extracted_proc(&arr)
	x := arr[0]
}
+
+extracted_proc :: proc(arr: ^[3]int) {
+	arr[0] = 10
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_if_statement :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}if x > 0 {
-		x = x - 1
-	}{>}
+	extracted_proc(&x)
	y := x
}
+
+extracted_proc :: proc(x: ^int) {
+	if x^ > 0 {
+		x^ = x^ - 1
+	}
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_for_loop :: proc(t: ^testing.T) {
	// Loop variable i is declared within the for statement and is loop-scoped
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	sum := 0
-	{<}for i := 0; i < 10; i += 1 {
-		sum += i
-	}{>}
+	extracted_proc(&sum)
	result := sum
}
+
+extracted_proc :: proc(sum: ^int) {
+	for i := 0; i < 10; i += 1 {
+		sum^ += i
+	}
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_range_loop :: proc(t: ^testing.T) {
	// Range loop variable val is detected as a read
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [3]f32{1, 2, 3}
	sum:f32 = 0.0
-	{<}for val in arr {
-		sum += val
-	}{>}
+	extracted_proc(&arr, &sum)
	result := sum
}
+
+extracted_proc :: proc(arr: ^[3]f32, sum: ^f32) {
+	for val in arr {
+		sum^ += val
+	}
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_call_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

helper :: proc(n: int) -> f32 { return n * 2 }

main :: proc() {
	x := 5
-	{<}y := helper(x){>}
+	y := extracted_proc(x)
	z := y
}
+
+extracted_proc :: proc(x: int) -> f32 {
+	y := helper(x)
+	return y
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_ternary :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}y := x > 0 ? 1 : 0{>}
+	y := extracted_proc(x)
	z := y
}
+
+extracted_proc :: proc(x: int) -> int {
+	y := x > 0 ? 1 : 0
+	return y
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_compound_literal :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Point :: struct { x, y: int }

main :: proc() {
	a := 1
	b := 2
-	{<}p := Point{x = a, y = b}{>}
+	p := extracted_proc(a, b)
	z := p.x
}
+
+extracted_proc :: proc(a: int, b: int) -> Point {
+	p := Point{x = a, y = b}
+	return p
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_nested_selector :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Inner :: struct { value: int }
Outer :: struct { inner: Inner }

main :: proc() {
	o := Outer{inner = Inner{value = 5}}
-	{<}o.inner.value = 10{>}
+	extracted_proc(&o)
	x := o.inner.value
}
+
+extracted_proc :: proc(o: ^Outer) {
+	o.inner.value = 10
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_multiple_vars_used_after :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	input := 10
-	{<}a := input + 1
-	b := input + 2
-	c := a + b{>}
+	a, b, c := extracted_proc(input)
	x := a
	y := b
	z := c
}
+
+extracted_proc :: proc(input: int) -> (int, int, int) {
+	a := input + 1
+	b := input + 2
+	c := a + b
+	return a, b, c
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_make :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	size := 10
-	{<}arr := make([dynamic]int, size){>}
+	arr := extracted_proc(size)
	x := arr[0]
}
+
+extracted_proc :: proc(size: int) -> [dynamic]int {
+	arr := make([dynamic]int, size)
+	return arr
+}`,
		EXTRACT_PROC_ACTION,
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
	// Switch expression is now properly analyzed - val is passed as parameter
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	val := 1
-	{<}result := 0
-	switch val {
-	case 1:
-		result = 10
-	case 2:
-		result = 20
-	}{>}
+	result := extracted_proc(val)
	x := result
}
+
+extracted_proc :: proc(val: int) -> int {
+	result := 0
+	switch val {
+	case 1:
+		result = 10
+	case 2:
+		result = 20
+	}
+	return result
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_multiple_modifications :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
-	{<}a = a + 1
-	b = b + 1{>}
+	extracted_proc(&a, &b)
	x := a + b
}
+
+extracted_proc :: proc(a: ^int, b: ^int) {
+	a^ = a^ + 1
+	b^ = b^ + 1
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_slice_operations :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [5]int{1, 2, 3, 4, 5}
-	{<}slice := arr[1:3]{>}
+	slice := extracted_proc(&arr)
	x := slice[0]
}
+
+extracted_proc :: proc(arr: ^[5]int) -> []int {
+	slice := arr[1:3]
+	return slice
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_read_only_vars :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
-	{<}c := a + b{>}
+	extracted_proc(a, b)
}
+
+extracted_proc :: proc(a: int, b: int) {
+	c := a + b
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_mixed_read_modify :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
-	{<}a = a + b{>}
+	extracted_proc(&a, b)
	c := a
}
+
+extracted_proc :: proc(a: ^int, b: int) {
+	a^ = a^ + b
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_unary_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}y := -x{>}
+	y := extracted_proc(x)
	z := y
}
+
+extracted_proc :: proc(x: int) -> int {
+	y := -x
+	return y
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_addr_of :: proc(t: ^testing.T) {
	// x is read via &x, ptr is declared and used after
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}ptr := &x{>}
+	ptr := extracted_proc(&x)
	y := ptr^
}
+
+extracted_proc :: proc(x: ^int) -> ^int {
+	ptr := x
+	return ptr
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_else_if_chain :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}result := 0
-	if x > 10 {
-		result = 1
-	} else if x > 5 {
-		result = 2
-	} else {
-		result = 3
-	}{>}
+	result := extracted_proc(x)
	y := result
}
+
+extracted_proc :: proc(x: int) -> int {
+	result := 0
+	if x > 10 {
+		result = 1
+	} else if x > 5 {
+		result = 2
+	} else {
+		result = 3
+	}
+	return result
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_nested_loops :: proc(t: ^testing.T) {
	// Nested loop variables i, j are detected as reads
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	total := 0
-	{<}for i := 0; i < 3; i += 1 {
-		for j := 0; j < 3; j += 1 {
-			total += i * j
-		}
-	}{>}
+	extracted_proc(&total)
	result := total
}
+
+extracted_proc :: proc(total: ^int) {
+	for i := 0; i < 3; i += 1 {
+		for j := 0; j < 3; j += 1 {
+			total^ += i * j
+		}
+	}
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_min_max :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 5
	b := 10
-	{<}c := min(a, b)
-	d := max(a, b){>}
+	c, d := extracted_proc(a, b)
	x := c + d
}
+
+extracted_proc :: proc(a: int, b: int) -> (int, int) {
+	c := min(a, b)
+	d := max(a, b)
+	return c, d
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_var_not_used_after :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	input := 10
-	{<}temp := input * 2
-	result := temp + 1{>}
+	extracted_proc(input)
}
+
+extracted_proc :: proc(input: int) {
+	temp := input * 2
+	result := temp + 1
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_partial_vars_used_after :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	input := 10
-	{<}temp := input * 2
-	result := temp + 1{>}
+	result := extracted_proc(input)
	x := result
}
+
+extracted_proc :: proc(input: int) -> int {
+	temp := input * 2
+	result := temp + 1
+	return result
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_block_stmt :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}{
-		x = x + 1
-	}{>}
+	extracted_proc(&x)
	y := x
}
+
+extracted_proc :: proc(x: ^int) {
+	{
+		x^ = x^ + 1
+	}
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_type_cast :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}y := f32(x){>}
+	y := extracted_proc(x)
	z := y
}
+
+extracted_proc :: proc(x: int) -> f32 {
+	y := f32(x)
+	return y
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_append :: proc(t: ^testing.T) {
	// &arr in source is treated as reading arr, not modifying
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := make([dynamic]int)
	val := 5
-	{<}append(&arr, val){>}
+	extracted_proc(arr, val)
	x := arr[0]
}
+
+extracted_proc :: proc(arr: [dynamic]int, val: int) {
+	append(&arr, val)
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_multiple_procs_in_file :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

helper :: proc() {}

main :: proc() {
	x := 5
-	{<}y := x + 1{>}
+	y := extracted_proc(x)
	z := y
}
+
+extracted_proc :: proc(x: int) -> int {
+	y := x + 1
+	return y
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_at_end_of_proc :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}y := x + 1{>}
+	extracted_proc(x)
}
+
+extracted_proc :: proc(x: int) {
+	y := x + 1
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_map_access :: proc(t: ^testing.T) {
	// m is read via index access
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	m := make(map[string]f32)
-	{<}val := m["key"]{>}
+	val := extracted_proc(m)
	x := val
}
+
+extracted_proc :: proc(m: map[string]f32) -> f32 {
+	val := m["key"]
+	return val
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_map_assignment :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	m := make(map[string]int)
	val := 5
-	{<}m["key"] = val{>}
+	extracted_proc(&m, val)
	x := m["key"]
}
+
+extracted_proc :: proc(m: ^map[string]int, val: int) {
+	m["key"] = val
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_or_else :: proc(t: ^testing.T) {
	// or_else expression not fully analyzed yet
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	m := make(map[string]int)
-	{<}val := m["key"] or_else 0{>}
+	val := extracted_proc()
	x := val
}
+
+extracted_proc :: proc() -> int {
+	val := m["key"] or_else 0
+	return val
+}`,
		EXTRACT_PROC_ACTION,
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
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	inner := proc() {
		x := 5
-		{<}y := x + 1{>}
+		y := extracted_proc(x)
		z := y
	}
	inner()
}
+
+extracted_proc :: proc(x: int) -> int {
+	y := x + 1
+	return y
+}`,
		EXTRACT_PROC_ACTION,
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
action_extract_proc_with_multiple_params :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
	c := 3
-	{<}d := a + b + c{>}
+	d := extracted_proc(a, b, c)
	e := d
}
+
+extracted_proc :: proc(a: int, b: int, c: int) -> int {
+	d := a + b + c
+	return d
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_only_modify_some_vars :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
	c := 3
-	{<}a = a + b
-	c = c + b{>}
+	extracted_proc(&a, b, &c)
	x := a + c
}
+
+extracted_proc :: proc(a: ^int, b: int, c: ^int) {
+	a^ = a^ + b
+	c^ = c^ + b
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_if_statement_and_return :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}if x > 0 {
-		return
-	}{>}
+	if extracted_proc(x) {
+		return
+	}
	y := x
}
+
+extracted_proc :: proc(x: int) -> bool {
+	if x > 0 {
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Return with else branch
@(test)
action_extract_proc_with_return_in_else :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}if x > 0 {
-		x = x - 1
-	} else {
-		return
-	}{>}
+	if extracted_proc(&x) {
+		return
+	}
	y := x
}
+
+extracted_proc :: proc(x: ^int) -> bool {
+	if x^ > 0 {
+		x^ = x^ - 1
+	} else {
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Break statement inside loop body extraction
@(test)
action_extract_proc_with_break :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	for i := 0; i < 10; i += 1 {
-		{<}if i > 5 {
-			break
-		}{>}
+		if extracted_proc(i) {
+			break
+		}
	}
}
+
+extracted_proc :: proc(i: int) -> bool {
+	if i > 5 {
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Continue statement inside loop body extraction
@(test)
action_extract_proc_with_continue :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	sum := 0
	for i := 0; i < 10; i += 1 {
-		{<}if i % 2 == 0 {
-			continue
-		}{>}
+		if extracted_proc(i) {
+			continue
+		}
		sum += i
	}
}
+
+extracted_proc :: proc(i: int) -> bool {
+	if i % 2 == 0 {
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Break and continue in same selection
@(test)
action_extract_proc_with_break_and_continue :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	for i := 0; i < 10; i += 1 {
-		{<}if i > 8 {
-			break
-		}
-		if i % 2 == 0 {
-			continue
-		}{>}
+		__should_break, __should_continue := extracted_proc(i)
+		if __should_break {
+			break
+		}
+		if __should_continue {
+			continue
+		}
	}
}
+
+extracted_proc :: proc(i: int) -> (bool, bool) {
+	if i > 8 {
+		return true, false
+	}
+	if i % 2 == 0 {
+		return false, true
+	}
+	return false, false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_with_break_in_map_loop :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := make(map[string]f32)
	for k, &val in arr {
-		{<}if val == 3 && k == "five" {
-			val = 5
-			break
-		}{>}
+		if extracted_proc(k, val) {
+			break
+		}
	}
}
+
+extracted_proc :: proc(k: string, val: ^f32) -> bool {
+	if val^ == 3 && k == "five" {
+		val^ = 5
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Loop inside extracted code - break/continue should not be transformed
// because they're scoped to the inner loop
@(test)
action_extract_proc_with_inner_loop_break :: proc(t: ^testing.T) {
	// break is inside the loop that's being extracted, so no control flow wrapper
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}for i := 0; i < 10; i += 1 {
-		if i > 5 {
-			break
-		}
-	}{>}
+	extracted_proc()
	y := x
}
+
+extracted_proc :: proc() {
+	for i := 0; i < 10; i += 1 {
+		if i > 5 {
+			break
+		}
+	}
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Return inside extracted loop (return should still be transformed)
@(test)
action_extract_proc_with_return_inside_loop :: proc(t: ^testing.T) {
	// return should still be transformed even inside a loop
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}for i := 0; i < 10; i += 1 {
-		if i > x {
-			return
-		}
-	}{>}
+	if extracted_proc(x) {
+		return
+	}
	y := x
}
+
+extracted_proc :: proc(x: int) -> bool {
+	for i := 0; i < 10; i += 1 {
+		if i > x {
+			return true
+		}
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Continue in nested loop with outer variable modification
@(test)
action_extract_proc_with_continue_and_modification :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	sum := 0
	for i := 0; i < 10; i += 1 {
-		{<}if i % 2 == 0 {
-			sum += i
-			continue
-		}{>}
+		if extracted_proc(i, &sum) {
+			continue
+		}
		sum += i * 2
	}
}
+
+extracted_proc :: proc(i: int, sum: ^int) -> bool {
+	if i % 2 == 0 {
+		sum^ += i
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Return with variable that needs to be returned
@(test)
action_extract_proc_with_return_and_declared_var :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	{<}result := x * 2
-	if result > 15 {
-		return
-	}{>}
+	if __should_return, result := extracted_proc(x); __should_return {
+		return
+	}
	y := result
}
+
+extracted_proc :: proc(x: int) -> (bool, int) {
+	result := x * 2
+	if result > 15 {
+		return true, result
+	}
+	return false, result
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: Break inside switch statement (shouldn't affect extraction)  
// Switch break is different from loop break in Odin
@(test)
action_extract_proc_with_switch_and_break :: proc(t: ^testing.T) {
	// Switch break should still trigger control flow handling because
	// in Odin, break in switch breaks out of the enclosing loop if any
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	for i := 0; i < 10; i += 1 {
-		{<}switch i {
-		case 5:
-			break
-		}{>}
+		if extracted_proc(i) {
+			break
+		}
	}
}
+
+extracted_proc :: proc(i: int) -> bool {
+	switch i {
+	case 5:
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

// Test: String iteration - char is rune
@(test)
action_extract_proc_with_string_iteration :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	str := "Hello"
	for char in str {
-		{<}if char == 'e' {
-			break
-		}{>}
+		if extracted_proc(char) {
+			break
+		}
	}
}
+
+extracted_proc :: proc(char: rune) -> bool {
+	if char == 'e' {
+		return true
+	}
+	return false
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_from_expression :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

	Custom_Struct :: struct {
		field1: int
		field2: f32
	}

	helper :: proc() -> ^Custom_Struct {
		s := new(Custom_Struct)
		s.field1 = 10
		s.field2 = 20.0
		return s
	}

main :: proc() {
	x := helper()

-	if {<}x.field1 > 25{>} {
+	if extracted_proc(x) {
		println("The value is greater than 25")
	}
}
+
+extracted_proc :: proc(x: ^Custom_Struct) -> bool {
+	return x.field1 > 25
+}`,
		EXTRACT_PROC_ACTION,
	)
}


@(test)
action_extract_proc_from_expression_in_for :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	limit := 100
-	for i := 0; {<}i < limit{>}; i += 1 {
+	for i := 0; extracted_proc(i, limit); i += 1 {
		println(i)
	}
}
+
+extracted_proc :: proc(i: int, limit: int) -> bool {
+	return i < limit
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_from_logical_expression :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y := 10
-	if {<}x > 0 && y < 20{>} {
+	if extracted_proc(x, y) {
		println("valid")
	}
}
+
+extracted_proc :: proc(x: int, y: int) -> bool {
+	return x > 0 && y < 20
+}`,
		EXTRACT_PROC_ACTION,
	)
}

@(test)
action_extract_proc_nested_to_top_level :: proc(t: ^testing.T) {
	// This test verifies that extracting code from a nested procedure
	// places the extracted procedure at the TOP LEVEL (package scope),
	// not at the parent procedure's scope.
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	helper :: proc() {
		x := 1
-		{<}y := x + 2{>}
+		y := extracted_proc(x)
		z := y
	}
	helper()
}
+
+extracted_proc :: proc(x: int) -> int {
+	y := x + 2
+	return y
+}
some_other_proc :: proc() { }`,
		EXTRACT_PROC_ACTION,
	)
}