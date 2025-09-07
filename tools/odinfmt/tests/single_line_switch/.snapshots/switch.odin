package single_line_switch

Barrr :: enum {
	A,
	B,
}

main :: proc() {
	bar: Barrr
	aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa := 1
	bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb := 2
	cccccccccccccccccccc := 3

	switch bar {
	case .A:
		foo := this_is_a_really_long_proc_name(
				aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,
				bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				cccccccccccccccccccc,
			)
	case .B: foo := this_is_a_really_long_proc_name(1, 2, 3)
	}
}

this_is_a_really_long_proc_name :: proc(a, b, c: int) -> int {
	return a + b + c
}
