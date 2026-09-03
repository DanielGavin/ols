package align_comments

basic_run :: proc() {
	x := 10 // first
	longer_var := 200 // second
	z := 3 // third
}

split_by_blank_line :: proc() {
	a := 1 // group one
	bb := 2 // group one

	ccc := 3 // group two
	dddd := 4 // group two
}

split_by_uncommented_line :: proc() {
	a := 1 // has a comment
	bb := 2
	ccc := 3 // separate group
}

split_by_indentation :: proc() {
	outer := 1 // outer scope
	if outer == 1 {
		inner := 2 // inner scope
	}
}

with_disabled_region :: proc() {
	before := 1 // before
	//odinfmt: disable
	messy      := 2 // untouched by alignment
	//odinfmt: enable
	after := 3 // after
}

Struct_Fields :: struct {
	a:   int, // field a
	bb:  int, // field b
	ccc: int, // field c
}

block_comments_stay_unaligned :: proc() {
	x := 1 /* not aligned */
	longer := 2 // line comment
}
