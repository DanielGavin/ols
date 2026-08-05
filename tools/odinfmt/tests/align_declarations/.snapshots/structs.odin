package align_declarations

Game :: struct {
	paddle     : Paddle,
	is_running : bool,
}

Player :: struct {
	name    : string,
	age     : u8,
	health  : uint,
	stamina : uint,
}

Entity :: struct {
	pos   : [3]f32,
	vel   : [3]f32,
	rot   : [3]f32,
	scale : [3]f32,
}

Vector3 :: struct {
	x : f32,
	y : f32,
	z : f32,
	w : f32,
}

Config :: struct {
	timeout : int,
	retries : int,
}

// Single field (no alignment needed)
Single :: struct {
	value : int,
}

State :: struct {
	ready   : bool,
	running : bool,
	error   : Error_Info,
	count   : int,
}

Multi_Names :: struct {
	a, b, c : int,
	x       : f32,
}
