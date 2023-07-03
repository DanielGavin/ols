package odinfmt_test


main :: proc() {
	_ = SameLine{a = 1, b = 2, c = 3}
	_ = MultiLine{
		a = 1,
		b = 2,
		c = 3,
	}
	_ = array_like{0, 1, 2, 3}
	_ = array_like{
		0, 1,
		2, 3,
	}
	_ = array_like{
		0, 1,
		2, 3,
	}
	_ = array_like{
		0, 1,
		2, 3,
	}
	_ = array_like{
		0, 1,
		2,
		3, 4, 5, 6, 7,
		8,
	}

	sort.sort(sort.Interface{
		len = proc(it: sort.Interface) -> int {
			c := 2
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			b := 1
		},
		swap = proc(it: sort.Interface, i, j: int) {
			a := 2
			c := 3
		},
		collection = &polygon,
	})
}
