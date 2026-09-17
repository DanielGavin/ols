package tests

import "core:testing"

import test "src:testing"

@(test)
unused_imports_skip_invalid_file :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
Value :: \
`,
	}

	test.expect_invalid_file_skips_unused_import_resolution(t, &src)
}

@(test)
index_updates_preserve_and_invalidate_resolution_caches :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
Value :: 42
`,
	}

	test.expect_index_updates_preserve_and_invalidate_resolution_caches(t, &src)
}
