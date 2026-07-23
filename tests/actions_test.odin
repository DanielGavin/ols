package tests

import "core:testing"

import test "src:testing"

import "src:server"

@(test)
action_remove_unused_import_when_stmt :: proc(t: ^testing.T) {
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

@(test)
action_organize_imports_add_imports :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
			main :: proc() {
				fmt.prin{*}tln("hello")
			}
		`,
		packages = {},
	}

	ctx := server.CodeActionContext {
		only = {"source"},
	}

	test.expect_action(t, &source, {"organize imports"}, ctx)
}
