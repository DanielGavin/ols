package odinfmt_test

main :: proc() {
	#no_bounds_check for i := 0; i < 100; i += 1 {
	}

	#no_bounds_check buf = buf[8:]
}
