package tests

import "core:testing"
import test "src:testing"

@(test)
action_populate_empty_inline_enum_switch :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
E :: enum { A, B }
main :: proc() {
	e: E
	swi{*}tch e {}
}
`,
	}
	test.expect_action_applied(t, &source, "populate remaining switch cases", `package main
E :: enum { A, B }
main :: proc() {
	e: E
	switch e {
	case .A:
	case .B:
	}
}
`)
}

@(test)
action_populate_empty_inline_union_switch :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
main :: proc() {
	u: union {int, string}
	swi{*}tch v in u {}
}
`,
	}
	test.expect_action_applied(t, &source, "populate remaining switch cases", `package main
main :: proc() {
	u: union {int, string}
	switch v in u {
	case int:
	case string:
	}
}
`)
}

@(test)
action_populate_multiline_switch_preserves_comment :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
E :: enum { A, B }
main :: proc() {
	e: E
	swi{*}tch e {
	case .A:
		// Keep this comment with the existing case.
	}
}
`,
	}
	test.expect_action_applied(t, &source, "populate remaining switch cases", `package main
E :: enum { A, B }
main :: proc() {
	e: E
	switch e {
	case .A:
		// Keep this comment with the existing case.
	case .B:
	}
}
`)
}
