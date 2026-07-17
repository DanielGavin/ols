package tests

import "core:testing"

import test "src:testing"

@(test)
action_remove_unsed_import_when_stmt :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		import "core:fm{*}t"

		when true {
			main :: proc() {
				_ = fmt.printf
			}
		}
		`,
		packages = {},
	}

	test.expect_action(t, &source, {})
}
