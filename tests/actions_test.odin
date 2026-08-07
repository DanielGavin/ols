#+feature dynamic-literals
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

@(private = "file")
organize_imports_packages :: proc() -> []test.Package {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "fmt", source = `package fmt
println :: proc(args: ..any) {}
`})

	append(
		&packages,
		test.Package {
			pkg = "strings",
			source = `package strings
trim_space :: proc(s: string) -> string { return s }
`,
		},
	)

	append(&packages, test.Package{pkg = "log", source = `package log
info :: proc(args: ..any) {}
`})

	return packages[:]
}

@(private = "file")
organize_imports_context :: server.CodeActionContext {
	only = {"source"},
}

@(test)
action_organize_imports_add_and_remove :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

import "core:log"
import "core:fmt"

main :: proc() {
	fmt.pri{*}ntln("hello!")
	fmt.println(strings.trim_space(" world "))
}
`,
		packages = organize_imports_packages(),
		collections = {"core" = "test"},
	}

	test.expect_action_applied(
		t,
		&source,
		"organize imports",
		`package main

import "core:strings"
import "core:fmt"

main :: proc() {
	fmt.println("hello!")
	fmt.println(strings.trim_space(" world "))
}
`,
		organize_imports_context,
	)
}

@(test)
action_organize_imports_add_and_remove_without_empty_line :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main
import "core:log"
import "core:fmt"

main :: proc() {
	fmt.pri{*}ntln("hello!")
	fmt.println(strings.trim_space(" world "))
}
`,
		packages = organize_imports_packages(),
		collections = {"core" = "test"},
	}

	test.expect_action_applied(
		t,
		&source,
		"organize imports",
		`package main
import "core:strings"
import "core:fmt"

main :: proc() {
	fmt.println("hello!")
	fmt.println(strings.trim_space(" world "))
}
`,
		organize_imports_context,
	)
}

@(test)
action_organize_imports_remove_only :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

import "core:log"
import "core:fmt"

main :: proc() {
	fmt.pri{*}ntln("hello!")
}
`,
		packages = organize_imports_packages(),
		collections = {"core" = "test"},
	}

	test.expect_action_applied(
		t,
		&source,
		"organize imports",
		`package main

import "core:fmt"

main :: proc() {
	fmt.println("hello!")
}
`,
		organize_imports_context,
	)
}

@(test)
action_organize_imports_remove_last_line :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

import "core:fmt"

main :: proc() {
	fmt.pri{*}ntln("hello!")
}

import "core:log"`,
		packages = organize_imports_packages(),
		collections = {"core" = "test"},
	}

	test.expect_action_applied(
		t,
		&source,
		"organize imports",
		`package main

import "core:fmt"

main :: proc() {
	fmt.println("hello!")
}

`,
		organize_imports_context,
	)
}

@(test)
action_organize_imports_add_to_bottom :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

import "core:log"
import "core:fmt"

main :: proc() {
	fmt.pri{*}ntln("hello!")
	fmt.println(strings.trim_space(" world "))
}
`,
		packages = organize_imports_packages(),
		collections = {"core" = "test"},
	}

	source.config.enable_add_import_to_bottom = true

	test.expect_action_applied(
		t,
		&source,
		"organize imports",
		`package main

import "core:fmt"

main :: proc() {
	fmt.println("hello!")
	fmt.println(strings.trim_space(" world "))
}
import "core:strings"
`,
		organize_imports_context,
	)
}

@(test)
action_organize_imports_add_to_bottom_with_removed_bottom_line :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

main :: proc() {
	fmt.pri{*}ntln("hello!")
	fmt.println(strings.trim_space(" world "))
}

import "core:fmt"
import "core:log"`,
		packages = organize_imports_packages(),
		collections = {"core" = "test"},
	}

	source.config.enable_add_import_to_bottom = true

	test.expect_action_applied(
		t,
		&source,
		"organize imports",
		`package main

main :: proc() {
	fmt.println("hello!")
	fmt.println(strings.trim_space(" world "))
}

import "core:fmt"
import "core:strings"
`,
		organize_imports_context,
	)
}
