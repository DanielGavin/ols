package common

import "base:runtime"

import "core:mem"

Scratch_Allocator :: struct {
	data:               []byte,
	curr_offset:        int,
	prev_allocation:    rawptr,
	backup_allocator:   mem.Allocator,
	leaked_allocations: [dynamic][]byte,
}

scratch_allocator_init :: proc(s: ^Scratch_Allocator, size: int, backup_allocator := context.allocator) {
	s.data, _ = mem.make_aligned([]byte, size, 2 * align_of(rawptr), backup_allocator)
	s.curr_offset = 0
	s.prev_allocation = nil
	s.backup_allocator = backup_allocator
	s.leaked_allocations.allocator = backup_allocator
}

scratch_allocator_destroy :: proc(s: ^Scratch_Allocator) {
	if s == nil {
		return
	}
	for ptr in s.leaked_allocations {
		mem.free_bytes(ptr, s.backup_allocator)
	}
	delete(s.leaked_allocations)
	delete(s.data, s.backup_allocator)
	s^ = {}
}

scratch_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {

	s := (^Scratch_Allocator)(allocator_data)

	if s.data == nil {
		DEFAULT_BACKING_SIZE :: 1 << 22
		if !(context.allocator.procedure != scratch_allocator_proc && context.allocator.data != allocator_data) {
			panic("cyclic initialization of the scratch allocator with itself")
		}
		scratch_allocator_init(s, DEFAULT_BACKING_SIZE)
	}

	size := size

	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		size = mem.align_forward_int(size, alignment)

		switch {
		case s.curr_offset + size <= len(s.data):
			start := uintptr(raw_data(s.data))
			ptr := start + uintptr(s.curr_offset)
			ptr = mem.align_forward_uintptr(ptr, uintptr(alignment))
			mem.zero(rawptr(ptr), size)

			s.prev_allocation = rawptr(ptr)
			offset := int(ptr - start)
			s.curr_offset = offset + size
			return mem.byte_slice(rawptr(ptr), size), nil
		}

		a := s.backup_allocator
		if a.procedure == nil {
			a = context.allocator
			s.backup_allocator = a
		}

		ptr, err := mem.alloc_bytes(size, alignment, a, loc)
		if err != nil {
			return ptr, err
		}
		if s.leaked_allocations == nil {
			s.leaked_allocations = make([dynamic][]byte, a)
		}
		append(&s.leaked_allocations, ptr)

		if logger := context.logger; logger.lowest_level <= .Warning {
			if logger.procedure != nil {
				logger.procedure(
					logger.data,
					.Warning,
					"mem.Scratch_Allocator resorted to backup_allocator",
					logger.options,
					loc,
				)
			}
		}

		return ptr, err

	case .Free:
	case .Free_All:
		s.curr_offset = 0
		s.prev_allocation = nil
		for ptr in s.leaked_allocations {
			mem.free_bytes(ptr, s.backup_allocator)
		}
		clear(&s.leaked_allocations)

	case .Resize, .Resize_Non_Zeroed:
		begin := uintptr(raw_data(s.data))
		end := begin + uintptr(len(s.data))
		old_ptr := uintptr(old_memory)

		data, err := scratch_allocator_proc(allocator_data, .Alloc, size, alignment, old_memory, old_size, loc)
		if err != nil {
			return data, err
		}

		runtime.copy(data, mem.byte_slice(old_memory, old_size))
		_, err = scratch_allocator_proc(allocator_data, .Free, 0, alignment, old_memory, old_size, loc)
		return data, err

	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Free, .Free_All, .Resize, .Query_Features}
		}
		return nil, nil
	case .Query_Info:
		return nil, nil
	}

	return nil, nil
}

scratch_allocator :: proc(allocator: ^Scratch_Allocator) -> mem.Allocator {
	return mem.Allocator{procedure = scratch_allocator_proc, data = allocator}
}
