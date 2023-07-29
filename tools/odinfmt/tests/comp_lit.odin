package odinfmt_test 


main :: proc() {
	T :: struct {
		a, b, c, d: int,
	}
	_ = T{0,0,0,0}
	_ = T{
		0,0,0,0,
	}
	_ = T{
		0,
		  0,
		0,
		  0,
	}
	_ = T{
		0,0,
		0,0,
	}
	_ = T{a=0,b=0,c=0,d=0}
	_ = T{
		a=0,b=0,c=0,d=0,
	}
	_ = T{
		a=0,
		b=0,
		c=0,
		d=0,
	}
	_ = T{
		a=0,b=0,
		c=0,d=0,
	}

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


