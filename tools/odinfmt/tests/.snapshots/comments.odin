package odinfmt_test

//Comments are really important

GetPhysicsBody :: proc(index: int) -> PhysicsBody // Returns a physics body of the bodies pool at a specific index


line_comments :: proc() {


	// comment
	thing: int
}


multiline_comments :: proc() {

	/* hello 
    there*/

	// comment
	thing: int
}


line_comments_one_line_seperation :: proc() {


	// comment

	thing: int
}


//More comments YAY

bracket_comments_alignment :: proc() {
	{ 	// Describe block
		a := 10
		// etc..
	}
}

empty_odin_fmt_block :: proc() {
	//odinfmt: disable
	//a := 10
	//odinfmt: enable
}


disabled_comment_after_normal_comments :: proc() {
	// comment
	// hello
	
    //odinfmt: disable
	return true
    //odinfmt: enable
}

disabled_comments_with_multiple_statements_one_lined :: proc() {
	//odinfmt: disable
	i:int;b:int
	//odinfmt: enable
}

//odinfmt: disable
AH :: Reg { index = 0b000, size  = .Bits_8H }
//
AL :: Reg { index = 0b000, size  = .Bits_8 }
//
AX :: Reg { index = 0b000, size  = .Bits_16 }
//
EAX :: Reg { index = 0b000, size  = .Bits_32 }

//odinfmt: enable
Instruction :: struct {
	mnemonic: Mnemonic,
	prefixes: LegacyPrefixes,
	operands: []Operand,
}

// odinfmt: disable
Bar :: struct{}
// odinfmt: enable

// Foo doc
Foo :: struct {}

// Merged trailing comments must not glue into `// first// second`.
check_two :: proc(cond: bool, msg: string) {}

two_trailing_comments_on_one_line :: proc() {
	check_two(
		len("a") > 0 && len("b") > 0, // first // second
		"message",
	)
}

// An attribute above the directive is still part of the declaration and must survive.
@(private)
//odinfmt:disable
guarded_private_helper :: proc() -> int {
	return 1
}
//odinfmt:enable

// A disable region inside a field list must be honoured, not dropped.
Guarded_Fields :: struct {
	//odinfmt:disable
	code:  string,
	//odinfmt:enable
	why:  string,
}
