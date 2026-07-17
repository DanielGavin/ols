package tests

import "core:testing"

import test "src:testing"

INVERT_IF_ACTION :: "Invert if"

@(test)
action_invert_if_simple :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := 5
	if x{*} >= 0 {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_invert_if_simple_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	if x{*} >= 0 {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x < 0 {
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_with_else :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	if x{*} == 0 {
		foo()
	} else {
		bar()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_invert_if_with_else_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	if x{*} == 0 {
		foo()
	} else {
		bar()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x != 0 {
		bar()
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_with_init :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x{*} := foo(); x < 0 {
		bar()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_invert_if_with_init_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x{*} := foo(); x < 0 {
		bar()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x := foo(); x >= 0 {
	} else {
		bar()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_not_on_if :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x :={*} 5
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	// Should not have the invert action when not on an if statement
	test.expect_action(t, &source, {})
}


@(test)
action_invert_if_inside_of_statement :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x != 0 {
		foo{*}()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	test.expect_action(t, &source, {})
}

@(test)
action_invert_if_not_eq :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x{*} != 0 {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x == 0 {
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_lt :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x{*} < 5 {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x >= 5 {
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_gt :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x{*} > 5 {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x <= 5 {
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_le :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x{*} <= 5 {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x > 5 {
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_negated :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if !x{*} {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x {
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_boolean :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	if x{*} {
		foo()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if !x {
	} else {
		foo()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_else_if_chain :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := something()
	if x{*} > 0 {
		statement1()
	} else if x < 0 {
		statement2()
	} else {
		statement3()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	expected := `if x <= 0 {
	if x < 0 {
		statement2()
	} else {
		statement3()
	}
	} else {
		statement1()
	}`

	test.expect_action_with_edit(t, &source, INVERT_IF_ACTION, expected)
}

@(test)
action_invert_if_not_on_else_if :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := something()
	if x > 0 {
		statement1()
	} else if x{*} < 0 {
		statement2()
	} else {
		statement3()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	// Should not have the invert action when on an else-if statement
	test.expect_action(t, &source, {})
}

@(test)
action_invert_if_not_on_else :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := something()
	if x > 0 {
		statement1()
	} else {
		statement3(){*}
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	// Should not have the invert action when in the else block (not on an if)
	test.expect_action(t, &source, {})
}

@(test)
action_invert_if_nested_in_else_if_body :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := something()
	if x > 0 {
		statement1()
	} else if x < 0 {
		if y{*} > 0 {
			statement2()
		}
	} else {
		statement3()
	}
}
`,
		packages = {},
		config = {enable_code_action_invert_if = true},
	}

	// Should have the invert action for an if statement nested inside an else-if body
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}
