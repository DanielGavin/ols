package tests

import "core:fmt"
import "core:testing"

import "src:server"
import test "src:testing"

@(test)
semantic_tokens :: proc(t: ^testing.T) {
	src := test.Source {
		main =
`package test
Proc_Type :: proc(a: string) -> int
my_function :: proc() {
	a := 2
	b := a
	c := 2 + b
}
`,
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 0, 9,  .Type,      {.ReadOnly}}, // [0]  Proc_Type
		{0, 18, 1, .Parameter, {}},          // [1]  a
		{0, 3, 6,  .Type,      {.ReadOnly}}, // [2]  string
		{0, 11, 3, .Type,      {.ReadOnly}}, // [3]  int
		{1, 0, 11, .Function,  {.ReadOnly}}, // [4]  my_function
		{1, 1, 1,  .Variable,  {}},          // [5]  a
		{1, 1, 1,  .Variable,  {}},          // [6]  b
		{0, 5, 1,  .Variable,  {}},          // [7]  a
		{1, 1, 1,  .Variable,  {}},          // [8]  c
		{0, 9, 1,  .Variable,  {}},          // [9]  b
	})
}

@(test)
semantic_tokens_global_consts :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Foo :: [2]f32
		Foo2 :: [2]f32{1,2}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3,  .Type,      {.ReadOnly}}, // [0]  Foo
		{0, 10, 3,  .Type,      {.ReadOnly}}, // [1]  f32
		{1, 2,  4,  .Variable,  {.ReadOnly}}, // [2]  Foo2
		{0, 11, 3,  .Type,      {.ReadOnly}}, // [3]  f32
	})
}

@(test)
semantic_tokens_literals_with_explicit_types :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Foo :: 1
		Foo2 : int : 1
		Foo3 :: cast(string) "hello"
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3, .Variable, {.ReadOnly}}, // [0]  Foo
		{1, 2,  4, .Variable, {.ReadOnly}}, // [1]  Foo2
		{0, 7,  3, .Type,     {.ReadOnly}}, // [2]  int
		{1, 2,  4, .Variable, {.ReadOnly}}, // [3]  Foo3
		{0, 13, 6, .Type,     {.ReadOnly}}, // [4]  string
	})
}
