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
		{0, 9, 1,  .Variable,  {}},          // [9] b
	})
}
