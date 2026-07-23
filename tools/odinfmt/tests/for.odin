package odinfmt_test

a :: proc() {
	bag: bit_set[0 ..< 10] = {5}
	for x in 0 ..< 10 do if x in bag {
			fmt.println(x)
		}
}

for_with_init :: proc () {
	foos : []string

	for x := 0 ;    foo in foos {
		x += len(foo)
	}   
}

long_range_headers_stay_on_one_line :: proc() {
	for expedition_index in passage.contract.ship_indices[:passage.contract.ship_count] do use(expedition_index)
	for _ in 0 ..< an_expression_long_enough_to_push_this_range_loop_header_past_the_formatter_width do tick()
}

broken_surrounding_document_keeps_range_header_on_one_line :: proc() {top_rail(s); draw_text(
		"THREE PROJECT SLOTS · INDUSTRY IS COMMITTED IMMEDIATELY",
		28,
		113,
		TYPE_SMALL_EMPHASIS,
		UX.info,
	)
	for project, i in s.campaign.projects {rect := R(28 + f32(i) * 405, 150, 380, 180); panel(rect, true); draw_fmt(
			rect.x + 22,
			rect.y + 20,
			TYPE_BODY_COMPACT,
			UX.dim,
			"SLOT %d",
			i + 1,
		)
	}
}
