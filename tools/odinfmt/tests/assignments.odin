package odinfmt_test

assignments :: proc() {
	a, b, c, d, e, f, res := &big.Int{}, &big.Int{}, &big.Int{}, &big.Int{}, &big.Int{}, &big.Int{}, &big.Int{}

}

ternary_when_assignment :: proc() {
	a := WGL_CONTEXT_FLAGS_ARB when ODIN_DEBUG else 0
	b := ODIN_DEBUG ? WGL_CONTEXT_FLAGS_ARB : 0
}
