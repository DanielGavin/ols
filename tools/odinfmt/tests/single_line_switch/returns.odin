package single_line_switch

return_inline_literal :: proc() -> i8 {
	switch {
	case: 
		return i8{}
	}
}

T :: [4]u64

return_multiline_literal :: proc() -> T {
	switch {
	case: return T{
		11111111111111111111,
		2222222222222222222,
		3333333333333333333,
		4444444444444444444,
	}
	}
}
