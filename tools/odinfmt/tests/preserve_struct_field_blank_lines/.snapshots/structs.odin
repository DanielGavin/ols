package preserve_struct_field_blank_lines

Settings :: struct {
	window_width:  int,
	window_height: int,
	target_fps:    int,

	fullscreen:    bool,
	vertical_sync: bool,
}

With_Comments :: struct {
	first:  int, // trailing comment

	// The second group.
	second: int,

	// The third group follows this comment without a blank line.
	third:  int,
}

Capped_By_Newline_Limit :: struct {
	first:  int,


	second: int,
}
