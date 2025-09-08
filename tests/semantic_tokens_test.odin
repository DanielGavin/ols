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
		Foo3 :: Foo
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3,  .Type,      {.ReadOnly}}, // [0]  Foo
		{0, 10, 3,  .Type,      {.ReadOnly}}, // [1]  f32
		{1, 2,  4,  .Variable,  {.ReadOnly}}, // [2]  Foo2
		{0, 11, 3,  .Type,      {.ReadOnly}}, // [3]  f32
		{1, 2,  4,  .Type,      {.ReadOnly}}, // [4]  Foo3
		{0, 8,  3,  .Type,      {.ReadOnly}}, // [5]  Foo
	})
}

@(test)
semantic_tokens_literals_with_explicit_types :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Foo :: 1
		Foo2 : int : 1
		Foo3 :: cast(string) "hello"
		Foo4 :: cstring("hello")
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3, .Variable, {.ReadOnly}}, // [0]  Foo
		{1, 2,  4, .Variable, {.ReadOnly}}, // [1]  Foo2
		{0, 7,  3, .Type,     {.ReadOnly}}, // [2]  int
		{1, 2,  4, .Variable, {.ReadOnly}}, // [3]  Foo3
		{0, 13, 6, .Type,     {.ReadOnly}}, // [4]  string
		{1, 2,  4, .Variable, {.ReadOnly}}, // [5]  Foo4
		{0, 8,  7, .Type,     {.ReadOnly}}, // [6]  cstring
	})
}

@(test)
semantic_tokens_struct_fields :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo: Foo
			foo.bar = 2
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3,  .Struct,    {.ReadOnly}}, // [0]  Foo
		{1, 3,  3,  .Property,  {}},          // [1]  bar
		{0, 5,  3,  .Type,      {.ReadOnly}}, // [2]  int
		{3, 2,  4,  .Function,  {.ReadOnly}}, // [3]  main
		{1, 3,  3,  .Variable,  {}},          // [4]  foo
		{0, 5,  3,  .Struct,    {.ReadOnly}}, // [5]  Foo
		{1, 3,  3,  .Variable,  {}},          // [6]  foo
		{0, 4,  3,  .Property,  {}},          // [7]  bar
	})
}

@(test)
semantic_tokens_proc_return :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		foo :: proc() -> (ret: int) {
			ret += 1
			return
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3, .Function, {.ReadOnly}}, // [0]  foo
		{0, 18, 3, .Variable, {}},          // [1]  ret
		{0, 5,  3, .Type,     {.ReadOnly}}, // [2]  proc
		{1, 3,  3, .Variable, {}},          // [3]  ret
	})
}
