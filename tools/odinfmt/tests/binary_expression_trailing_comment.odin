package odinfmt_test

binary_expression_trailing_comment :: proc() {
	bus: u8 = 0
	device: u8 = 1
	function: u8 = 0
	offset: u8 = 0x10
	address :=
		u32(1) << 31 | // comment on value
		(u32(bus) << 16) |
		(u32(device) << 11) |
		(u32(function) << 8) |
		(u32(offset) & 0xFC)
	_ = address
}
