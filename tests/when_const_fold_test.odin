package tests

import "core:testing"

import test "src:testing"

// #1562: package-level consts used in `when` (MAP_ENABLED :: !ODIN_BEDROCK)

@(test)
ast_when_const_map_enabled_pattern :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		// Mirrors base/runtime/core_builtin.odin
		MAP_ENABLED :: !ODIN_BEDROCK

		when MAP_ENABLED {
			map_insert_like :: proc(m: ^map[int]int, key: int, value: int) {}
		}

		main :: proc() {
			map_insert_li{*}ke
		}
		`,
		packages = {},
	}

	test.expect_hover(
		t,
		&source,
		"test.map_insert_like :: proc(m: ^map[int]int, key: int, value: int)",
	)
}

@(test)
ast_when_const_true_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		ALWAYS :: true

		when ALWAYS {
			visible :: proc() {}
		}

		main :: proc() {
			visib{*}le
		}
		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.visible :: proc()")
}

@(test)
ast_when_const_false_skips_body :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		NEVER :: false

		when NEVER {
			hidden :: proc() {}
		} else {
			shown :: proc() {}
		}

		main :: proc() {
			sho{*}wn
		}
		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.shown :: proc()")
}

@(test)
ast_when_const_chain :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		A :: true
		B :: A
		C :: B && true

		when C {
			chained :: proc() {}
		}

		main :: proc() {
			chain{*}ed
		}
		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.chained :: proc()")
}

@(test)
ast_when_direct_not_define_still_works :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		when !ODIN_BEDROCK {
			direct :: proc() {}
		}

		main :: proc() {
			direc{*}t
		}
		`,
		packages = {},
	}

	test.expect_hover(t, &source, "test.direct :: proc()")
}

@(test)
ast_when_local_const_condition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		FLAG :: true

		main :: proc() {
			when FLAG {
				foo: i32 = 5
			} else {
				foo: i64 = 6
			}
			fo{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_docs(t, &source, "", {"test.foo: i32"})
}
