package tests

import "core:testing"
import "src:odin/format"

@(test)
format_binary_expression_trailing_comment :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	source := `package main
main :: proc() {
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
`
	expected := `package main
main :: proc() {
	bus: u8 = 0
	device: u8 = 1
	function: u8 = 0
	offset: u8 = 0x10
	address := u32(1) << 31 | // comment on value
		(u32(bus) << 16) | (u32(device) << 11) | (u32(function) << 8) | (u32(offset) & 0xFC)
	_ = address
}
`
	config := format.default_style
	config.newline_style = .LF
	formatted, ok := format.format("main.odin", source, config)
	testing.expect(t, ok)
	testing.expect_value(t, formatted, expected)
	again, again_ok := format.format("main.odin", formatted, config)
	testing.expect(t, again_ok)
	testing.expect_value(t, again, formatted)
}
