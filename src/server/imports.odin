package server

import "core:mem"
import "core:odin/ast"


fix_imports :: proc(document: ^Document) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, mem.Megabyte * 25))
	defer delete(arena.data)

	context.allocator = mem.arena_allocator(&arena)

	symbols_and_nodes := resolve_entire_file(document, .None)


}
