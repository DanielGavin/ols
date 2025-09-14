package single_line_switch

import "core:fmt"

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

Number :: union {
	int,
	uint,
}

f :: proc(
	very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_long_name: Number,
) {
	#partial switch value in
		very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_long_name {
	case:
		#partial switch value in
				very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_very_long_name {
			case int: fmt.println("Number is an integer")
			case: fmt.println("Number is not an integer")
			}
	}
}
