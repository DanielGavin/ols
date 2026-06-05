package tests

import "core:testing"

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
		{0, 5,  3, .Type,     {.ReadOnly}}, // [2]  int
		{1, 3,  3, .Variable, {}},          // [3]  ret
	})
}

@(test)
semantic_tokens_fixed_array_fields :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		main :: proc() {
			foo: [2]f32
			y := foo.x
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2, 4, .Function, {.ReadOnly}}, // [0]  main
		{1, 3, 3, .Variable, {}},          // [1]  foo
		{0, 8, 3, .Type,     {.ReadOnly}}, // [2]  f32
		{1, 3, 1, .Variable, {}},          // [3]  y
		{0, 5, 3, .Variable, {}},          // [4]  foo
		{0, 4, 1, .Property, {}},          // [5]  x
	})
}

@(test)
semantic_tokens_enum_member_default_param :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		bar :: proc(foo: Foo = .A) {}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3, .Enum,       {.ReadOnly}}, // [0]  Foo
		{1, 3,  1, .EnumMember, {}},          // [1]  A
		{1, 3,  1, .EnumMember, {}},          // [2]  B
		{3, 2,  3, .Function,   {.ReadOnly}}, // [3]  bar
		{0, 12, 3, .Parameter,  {}},          // [4]  foo
		{0, 5,  3, .Enum,       {.ReadOnly}}, // [5]  Foo
		{0, 7,  1, .EnumMember, {}},          // [6]  A
	})
}

@(test)
semantic_tokens_type_parameter :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Foo :: struct($A: typeid) {
			bar: A,
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3, .Struct,        {.ReadOnly}}, // [0]  Foo
		{0, 15, 1, .TypeParameter, {}},          // [1]  A
		{1, 3,  3, .Property,      {}},          // [2]  bar
		{0, 5,  1, .TypeParameter, {.ReadOnly}}, // [3]  A
	})
}

@(test)
semantic_tokens_poly_proc :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		foo :: proc(a: $A) -> A {
			return a
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3, .Function,      {.ReadOnly}}, // [0]  foo
		{0, 12, 1, .Parameter,     {}},          // [1]  a
		{0, 4,  1, .TypeParameter, {}},          // [2]  A
		{1, 10, 1, .Parameter,     {}},          // [3]  a
	})
}

@(test)
semantic_tokens_proc_group_selector :: proc(t: ^testing.T) {

	src := test.Source{
		main = `package test
		import "pkg"
		local_proc :: proc() {}
		group :: proc {
			local_proc,
			pkg.some_proc,
		}
		`,
		packages = {
			test.Package{
				pkg = "pkg",
				source = `package pkg
				some_proc :: proc() {}
				`,
			},
		},
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 10, 3, .Namespace, {}},            // [0]  pkg (import)
		{1, 2, 10, .Function,  {.ReadOnly}},   // [1]  local_proc
		{1, 2,  5, .Function,  {.ReadOnly}},   // [2]  group
		{1, 3, 10, .Function,  {.ReadOnly}},   // [3]  local_proc
		{1, 3,  3, .Namespace, {.ReadOnly}},   // [4]  pkg (selector expr)
		{0, 4,  9, .Function,  {.ReadOnly}},   // [5]  some_proc
	})
}

@(test)
semantic_tokens_fixed_capacity_dynamic_array :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		foo: [dynamic; 5]int
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2,  3, .Variable, {}},          // [0]  foo
		{0, 17, 3, .Type,     {.ReadOnly}}, // [1]  int
	})
}

@(test)
semantic_tokens_const_type_cast :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		GLOBAL_TRUE :: bool(true)
		GLOBAL_A    :: int(42)
		GLOBAL_B    :: cstring("hello")
		main :: proc() {
			TRUE :: bool(true)
			A    :: int(42)
			A    :: cstring("hello")
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		// Global scope
		{1, 2, 11, .Variable, {.ReadOnly}}, // [0]  GLOBAL_TRUE
		{0, 15, 4, .Type,     {.ReadOnly}}, // [1]  bool
		{1, 2,  8, .Variable, {.ReadOnly}}, // [2]  GLOBAL_A
		{0, 15, 3, .Type,     {.ReadOnly}}, // [3]  int
		{1, 2,  8, .Variable, {.ReadOnly}}, // [4]  GLOBAL_B
		{0, 15, 7, .Type,     {.ReadOnly}}, // [5]  cstring
		{1, 2,  4, .Function, {.ReadOnly}}, // [6]  main
		// Local scope
		{1, 3,  4, .Variable, {.ReadOnly}}, // [7]  TRUE
		{0, 8,  4, .Type,     {.ReadOnly}}, // [8]  bool
		{1, 3,  1, .Variable, {.ReadOnly}}, // [9]  A
		{0, 8,  3, .Type,     {.ReadOnly}}, // [10] int
		{1, 3,  1, .Variable, {.ReadOnly}}, // [11] B
		{0, 8,  7, .Type,     {.ReadOnly}}, // [12] cstring
	})
}

@(test)
semantic_tokens_const_alias_type_cast :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Bool   :: bool
		G_TRUE :: Bool(true)
		main :: proc() {
			TRUE :: Bool(true)
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		// Global scope
		{1, 2,  4, .Type,     {.ReadOnly}}, // [0]  Bool
		{0, 10, 4, .Type,     {.ReadOnly}}, // [1]  bool
		{1, 2,  6, .Variable, {.ReadOnly}}, // [2]  G_TRUE
		{0, 10, 4, .Type,     {.ReadOnly}}, // [3]  Bool
		{1, 2,  4, .Function, {.ReadOnly}}, // [4]  main
		// Local scope
		{1, 3,  4, .Variable, {.ReadOnly}}, // [5]  TRUE
		{0, 8,  4, .Type,     {.ReadOnly}}, // [6]  Bool
	})
}

@(test)
semantic_tokens_const_array :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		Vec   :: [2]f32
		G_VEC :: Vec{1, 2}
		main :: proc() {
			VEC :: Vec{1, 2}
		}
		`
	}

	test.expect_semantic_tokens(t, &src, {
		// Global scope
		{1, 2,  3, .Type,     {.ReadOnly}}, // [0]  Vec
		{0, 12, 3, .Type,     {.ReadOnly}}, // [1]  f32
		{1, 2,  5, .Variable, {.ReadOnly}}, // [2]  G_VEC
		{0, 9,  3, .Type,     {.ReadOnly}}, // [3]  Vec
		{1, 2,  4, .Function, {.ReadOnly}}, // [4]  main
		// Local scope
		{1, 3,  3, .Variable, {.ReadOnly}}, // [5]  VEC
		{0, 7,  3, .Type,     {.ReadOnly}}, // [6]  Vec
	})
}

@(test)
semantic_tokens_global_binary_expr :: proc(t: ^testing.T) {
	src := test.Source {
		main = `package test
		FOO :: 3 + 4
		BAR :: int(1) + int(2)
		`
	}

	test.expect_semantic_tokens(t, &src, {
		{1, 2, 3, .Variable, {.ReadOnly}}, // [0]  FOO
		{1, 2, 3, .Variable, {.ReadOnly}}, // [1]  BAR
		{0, 7, 3, .Type,     {.ReadOnly}}, // [2]  int
		{0, 9, 3, .Type,     {.ReadOnly}}, // [3]  int
	})
}

