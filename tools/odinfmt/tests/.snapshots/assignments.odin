package odinfmt_test

assignments :: proc() {
	a, b, c, d, e, f, res :=
		&big.Int{},
		&big.Int{},
		&big.Int{},
		&big.Int{},
		&big.Int{},
		&big.Int{},
		&big.Int{}

	value +=
		b4 *
		grad(
			seed,
			[3]i64{rbp.x, rbp.y - i_sign.y * PRIME_Y, rbp.z},
			[3]f32{ri.x, ri.y + f_sign.y, ri.z},
		)

	a :=
		(GRADIENTS_4D[gi] * delta.x + GRADIENTS_4D[gi | 1] * delta.y) +
		(GRADIENTS_4D[gi | 2] * delta.z + GRADIENTS_4D[gi | 3] * delta.w)
}

ternary_when_assignment :: proc() {
	a := WGL_CONTEXT_FLAGS_ARB when ODIN_DEBUG else 0
	b := ODIN_DEBUG ? WGL_CONTEXT_FLAGS_ARB : 0
}
