package no_align_declarations

Game :: struct {
	paddle :     Paddle,
	is_running : bool,
}

Player :: struct {
	name :    string,
	age :     u8,
	health :  uint,
	stamina : uint,
}

State :: struct {
	ready :   bool,
	running : bool,
	error :   Error_Info,
	count :   int,
}
