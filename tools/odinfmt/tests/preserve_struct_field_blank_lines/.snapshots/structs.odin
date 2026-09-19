package preserve_struct_field_blank_lines

Settings :: struct {
	window_width:  int,
	window_height: int,
	target_fps:    int,

	fullscreen:    bool,
	vertical_sync: bool,
}

Different_Section_Widths :: struct {
	short:       int,
	medium_name: int,

	much_longer_name: int,
	x:                int,
}

Comment_Within_Section :: struct {
	short:            int,
	// This comment does not start a new section.
	much_longer_name: int,
}

Subtype_Alignment :: struct {
	#subtype embedded: Embedded,
	regular:           int,
}

Block_Comment_Within_Section :: struct {
	short:            int,
	/* This comment contains an empty line.

	It does not create a new field section. */
	much_longer_name: int,
}

Trailing_Block_Comment_Within_Section :: struct {
	short:            int,
	/* This trailing comment contains an empty line.

	It does not create a new field section. */
	much_longer_name: int,
}

Block_Comment_Starts_Section :: struct {
	short: int,

	/* This comment starts after an actual field-section break.

	Its own empty line is irrelevant. */
	much_longer_name: int,
}

With_Comments :: struct {
	first: int, // trailing comment

	// The second group.
	second: int,

	// The third group follows this comment without a blank line.
	third: int,
}

Capped_By_Newline_Limit :: struct {
	first: int,


	second: int,
}
