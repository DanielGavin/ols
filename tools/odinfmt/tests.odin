package odinfmt_tests

import "core:os"
import "core:mem"

import "snapshot"


main :: proc() {
	init_global_temporary_allocator(mem.Megabyte * 100)

	if !snapshot.snapshot_directory("tests") {
		os.exit(1)
	}

}
