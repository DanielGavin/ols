package odinfmt_test

a :: proc() {
	bag: bit_set[0 ..< 10] = {5}
	for x in 0 ..< 10 do if x in bag {
		fmt.println(x)
	}
}

for_with_init :: proc() {
	foos: []string

	for x := 0; foo in foos {
		x += len(foo)
	}
}

long_range_headers_stay_on_one_line :: proc() {
	for expedition_index in passage.contract.ship_indices[:passage.contract.ship_count] do use(expedition_index)
	for _ in 0 ..< an_expression_long_enough_to_push_this_range_loop_header_past_the_formatter_width do tick()
}
