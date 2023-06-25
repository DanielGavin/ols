package odinfmt_test

a :: proc() {
	bag: bit_set[0 ..< 10] = {5}
	for x in 0 ..< 10 do if x in bag {
			fmt.println(x)
		}
}
