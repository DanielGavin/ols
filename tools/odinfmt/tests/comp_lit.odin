package odinfmt_test 


main :: proc() {
	sort.sort(sort.Interface{len = proc(it: sort.Interface) -> int {
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


