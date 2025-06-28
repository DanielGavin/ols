package odinfmt_test


calls :: proc() {
	aaaaaaaaaaaaa44444444777aaesult :=
		vk.CreateInsaaaaaadafaddddadwadawdwadawdawddgddaaaknce(
			my_really_cool_call(
				aaaaaaaaaaaaaaaaaaaaa,
				bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				cccccccccccccccccccccccccccccccc,
				ddddddddddddddddddddddddddddddddddddd,
			),
		)

	aaaaaaaaaaaaa44444444777aaesult =
		vk.CreateInsaaaaaadafaddddadwadawdwadawdawddgddaaaknce(
			my_really_cool_call(
				aaaaaaaaaaaaaaaaaaaaa,
				bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				cccccccccccccccccccccccccccccccc,
				ddddddddddddddddddddddddddddddddddddd,
			),
		)

	result := vk.CreateInsance(
		my_really_cool_call(
			aaaaaaaaaaaaaaaaaaaaa,
			bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
			cccccccccccccccccccccccccccccccc,
			ddddddddddddddddddddddddddddddddddddd,
		),
	)

	result = vk.CreateInsance(
		my_really_cool_call(
			aaaaaaaaaaaaaaaaaaaaa,
			bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
			cccccccccccccccccccccccccccccccc,
			ddddddddddddddddddddddddddddddddddddd,
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T{1, 2, 3},
			aaaaaaaaaaaaaaaaaaaaa,
			bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
			cccccccccccccccccccccccccccccccc,
			ddddddddddddddddddddddddddddddddddddd,
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T{a = 1, b = 2, c = 3},
			aaaaaaaaaaaaaaaaaaaaa,
			bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
			cccccccccccccccccccccccccccccccc,
			ddddddddddddddddddddddddddddddddddddd,
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T{1, 2, 3},
			aaaaaaaaaaaaaaaaaaaaa,
			bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
			cccccccccccccccccccccccccccccccc,
			ddddddddddddddddddddddddddddddddddddd,
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T{a = 1, b = 2, c = 3},
			aaaaaaaaaaaaaaaaaaaaa,
			bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
			cccccccccccccccccccccccccccccccc,
			ddddddddddddddddddddddddddddddddddddd,
		),
	)


	result = vk.CreateInsance(
		my_really_cool_call(
			T {
				aaaaaaaaaaaaaaaaaaaaa,
				bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				cccccccccccccccccccccccccccccccc,
				ddddddddddddddddddddddddddddddddddddd,
			},
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T {
				a = aaaaaaaaaaaaaaaaaaaaa,
				b = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				c = cccccccccccccccccccccccccccccccc,
				d = ddddddddddddddddddddddddddddddddddddd,
			},
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T {
				aaaaaaaaaaaaaaaaaaaaa,
				bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				cccccccccccccccccccccccccccccccc,
				ddddddddddddddddddddddddddddddddddddd,
				cccccccccccccccccccccccccccccccc,
				ddddddddddddddddddddddddddddddddddddd,
			},
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T {
				a = aaaaaaaaaaaaaaaaaaaaa,
				b = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				c = cccccccccccccccccccccccccccccccc,
				d = ddddddddddddddddddddddddddddddddddddd +
				ddddddddddddddddddddddddddddddddddddd,
			},
		),
	)
	result = vk.CreateInsance(
		my_really_cool_call(
			T {
				a = aaaaaaaaaaaaaaaaaaaaa,
				b = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,
				c = cccccccccccccccccccccccccccccccc,
				d = ddddddddddddddddddddddddddddddddddddd + 1,
			},
		),
	)

	_ = vk.CreateInsance(my_really_cool_call(1, 2, 3))
	_ = vk.CreateInsance(my_really_cool_call(1, 2, 3))
	_ = vk.CreateInsance(my_really_cool_call(1, 2, 3))
	_ = vk.CreateInsance(1, 2, 3)
	_ = vk.CreateInsance(1, 2, 3)
	_ = vk.CreateInsance(1)
	_ = vk.CreateInsance(Composite{a = 1, b = 2})
	_ = vk.CreateInsance(Composite{a = 1, b = 2})
	_ = vk.CreateInsance(Composite{a = 1, b = 2})
	_ = vk.CreateInsance(Composite{1, 2, 3, 4})
	_ = vk.CreateInsance(Composite{1, 2, 3, 4})
	_ = vk.CreateInsance(matrix[2, 2]i32{
			1, 2,
			3, 4,
		})
	_ = vk.CreateInsance(matrix[2, 2]i32{
			1, 2,
			3, 4,
		})

	test_2(
		Foo {
			field1 = 1,
			field2 = "hello",
			field3 = 1,
			field4 = "world",
			field5 = 1,
			field6 = "!",
			field7 = 1,
			field8 = 1,
		},
	)

	slice.sort_by(fis, proc(a, b: os.File_Info) -> bool {
		return a.name < b.name
	})

	test3(
		Foo {
			field1 = 1,
			field2 = "hello",
			field3 = 1,
			field4 = "world",
			field5 = 1,
			field6 = "!",
			field7 = 1,
			field8 = 1,
		},
	) or_return

	ab := short_call(10, false) or_return

	resuuuuuuuuult := add_to_long_list_of_values(
		fooooooooooooo,
		Foo {
			field1 = 1,
			field2 = "hello",
			field3 = 1,
			field4 = "world",
			field5 = 1,
			field6 = "!",
			field7 = 1,
			field8 = 1,
		},
		true,
	) or_return
}
