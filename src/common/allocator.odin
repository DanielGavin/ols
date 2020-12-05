package common

import "core:mem"

Scratch_Allocator :: struct {
	data:               []byte,
	curr_offset:        int,
	prev_allocation:   rawptr,
	backup_allocator:   mem.Allocator,
	leaked_allocations: [dynamic]rawptr,
}

scratch_allocator_init :: proc(s: ^Scratch_Allocator, size: int, backup_allocator := context.allocator) {
	s.data = mem.make_aligned([]byte, size, 2*align_of(rawptr), backup_allocator);
	s.curr_offset = 0;
	s.prev_allocation = nil;
	s.backup_allocator = backup_allocator;
	s.leaked_allocations.allocator = backup_allocator;
}

scratch_allocator_destroy :: proc(s: ^Scratch_Allocator) {
	if s == nil {
		return;
	}
	for ptr in s.leaked_allocations {
		free(ptr, s.backup_allocator);
	}
	delete(s.leaked_allocations);
	delete(s.data, s.backup_allocator);
	s^ = {};
}

scratch_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
                               size, alignment: int,
                               old_memory: rawptr, old_size: int, flags: u64 = 0, loc := #caller_location) -> rawptr {

	s := (^Scratch_Allocator)(allocator_data);

	if s.data == nil {
		DEFAULT_BACKING_SIZE :: 1<<22;
		if !(context.allocator.procedure != scratch_allocator_proc &&
		     context.allocator.data != allocator_data) {
			panic("cyclic initialization of the scratch allocator with itself");
		}
		scratch_allocator_init(s, DEFAULT_BACKING_SIZE);
	}

	size := size;

	switch mode {
	case .Alloc:
		size = mem.align_forward_int(size, alignment);

		switch {
		case s.curr_offset+size <= len(s.data):
			start := uintptr(raw_data(s.data));
			ptr := start + uintptr(s.curr_offset);
			ptr = mem.align_forward_uintptr(ptr, uintptr(alignment));
			mem.zero(rawptr(ptr), size);

			s.prev_allocation = rawptr(ptr);
			offset := int(ptr - start);
			s.curr_offset = offset + size;
			return rawptr(ptr);
		}
		a := s.backup_allocator;
		if a.procedure == nil {
			a = context.allocator;
			s.backup_allocator = a;
		}

		ptr := mem.alloc(size, alignment, a, loc);
		if s.leaked_allocations == nil {
			s.leaked_allocations = make([dynamic]rawptr, a);
		}
		append(&s.leaked_allocations, ptr);

		return ptr;

	case .Free:
	case .Free_All:
		s.curr_offset = 0;
		s.prev_allocation = nil;
		for ptr in s.leaked_allocations {
			free(ptr, s.backup_allocator);
		}
		clear(&s.leaked_allocations);

	case .Resize:
		begin := uintptr(raw_data(s.data));
		end := begin + uintptr(len(s.data));
		old_ptr := uintptr(old_memory);
		//if begin <= old_ptr && old_ptr < end && old_ptr+uintptr(size) < end {
		//	s.curr_offset = int(old_ptr-begin)+size;
		//	return old_memory;
		//}
		ptr := scratch_allocator_proc(allocator_data, .Alloc, size, alignment, old_memory, old_size, flags, loc);
		mem.copy(ptr, old_memory, old_size);
		scratch_allocator_proc(allocator_data, .Free, 0, alignment, old_memory, old_size, flags, loc);
		return ptr;

	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory);
		if set != nil {
			set^ = {.Alloc, .Free, .Free_All, .Resize, .Query_Features};
		}
		return set;

	case .Query_Info:
		return nil;
	}


	return nil;
}

scratch_allocator :: proc(allocator: ^Scratch_Allocator) -> mem.Allocator {
	return mem.Allocator{
		procedure = scratch_allocator_proc,
		data = allocator,
	};
}