package odinfmt_test

main :: proc() {
	// A literal written across multiple lines stays multiline.
	DrawTriangleStrip3D({
		{0, 0, 0},
		{1, 0, 0},
		{1, 1, 0},
		{0, 1, 0},
	}, color = {255, 128, 0, 255})

	// A literal written on a single line stays inlined.
	bar({1, 2, 3, 4}, color = {255, 128, 0, 255})

	// Arrays written across multiple lines stay multiline.
	values := [?]int{
		1,
		2,
		3,
	}

	// Single-line arrays stay inlined.
	inlined := [?]int{1, 2, 3}
}
