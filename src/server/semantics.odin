package server

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem/virtual"
import tf "core:odin/tool-format"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

import "src:common"

Semantics_Store :: struct {
	mutex: sync.Mutex,
	files: map[string]Semantics_File, // by `semantics_key`
}

Semantics_File :: struct {
	export:   ^Semantics_Export,
	exported: ^tf.Exported_File,
	version:  Maybe(int), // The version of the open document whose text was checked, and `nil` indicates it was checked from disk

	// When checked from disk (version == nil), the last version of the open document compared with the disk and whether they matched
	compared: Maybe(int),
	matches:  bool,
}

@(private = "file")
semantics_current :: proc(file: ^Semantics_File, document: ^Document) -> bool {
	current := document.version.? or_return
	if checked, ok := file.version.?; ok {
		return checked == current
	}
	if compared, ok := file.compared.?; ok && compared == current {
		return file.matches
	}
	// checked from disk, which an open document still is until it is edited
	disk, err := os.read_entire_file(document.fullpath, context.temp_allocator)
	file.compared = current
	file.matches = err == nil && string(disk) == string(document.text[:document.used_text])
	return file.matches
}

Semantics_Export :: struct {
	arena:     virtual.Arena,
	semantics: tf.Semantics,
	files:     int,
}

semantics_store: Semantics_Store

semantics_key :: proc(path: string, allocator := context.temp_allocator) -> string {
	when ODIN_OS == .Windows {
		return strings.to_lower(path, allocator)
	} else {
		return strings.clone(path, allocator)
	}
}

load_semantics :: proc(paths: []string, buffers: []Check_Buffer) {
	destroy_semantics_export :: proc(export: ^Semantics_Export) {
		virtual.arena_destroy(&export.arena)
		free(export, runtime.heap_allocator())
	}


	if len(paths) == 0 {
		return
	}
	start := time.now()

	versions := make(map[string]Maybe(int), len(buffers), context.temp_allocator)
	for b in buffers {
		versions[semantics_key(b.path)] = b.version
	}

	loaded := 0
	for path in paths {
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil {
			continue
		}

		export := new(Semantics_Export, runtime.heap_allocator())
		if aerr := virtual.arena_init_growing(&export.arena); aerr != nil {
			log.errorf("Failed to make an arena for the semantics in %q: %v", path, aerr)
			free(export, runtime.heap_allocator())
			continue
		}
		if uerr := tf.unmarshal_semantics(data, &export.semantics, virtual.arena_allocator(&export.arena)); uerr != nil {
			log.errorf("Failed to load the semantics in %q: %v", path, uerr)
			destroy_semantics_export(export)
			continue
		}

		sync.mutex_lock(&semantics_store.mutex)
		if semantics_store.files == nil {
			semantics_store.files = make(map[string]Semantics_File, 1024, runtime.heap_allocator())
		}
		for &exported in export.semantics.exported {
			key := semantics_key(export.semantics.files[exported.file])
			entry := &semantics_store.files[key]
			if entry == nil {
				owned := strings.clone(key, runtime.heap_allocator())
				semantics_store.files[owned] = {}
				entry = &semantics_store.files[owned]
			} else {
				entry.export.files -= 1
				if entry.export.files == 0 {
					destroy_semantics_export(entry.export)
				}
			}
			entry^ = {
				export   = export,
				exported = &exported,
				version  = versions[key],
			}
			export.files += 1
		}
		sync.mutex_unlock(&semantics_store.mutex)

		loaded += export.files
		if export.files == 0 {
			destroy_semantics_export(export)
		}
	}
	log.infof("Loaded the semantics of %d files in %v", loaded, time.since(start))
}

Semantic_Entity :: struct {
	name:   string,
	kind:   tf.Entity_Kind,
	pkg:    string,
	path:   string, // empty when it is not declared in a file (e.g. builtin)
	offset: int,
	type:   string,
	value:  string,
	size:   int,
	align:  int,
}

semantics_entity_at :: proc(
	document: ^Document,
	position: common.Position,
	allocator := context.temp_allocator,
) -> (
	entity: Semantic_Entity,
	start: int,
	ok: bool,
) {
	is_ident :: proc(c: u8) -> bool {
		return c == '_' || c >= 0x80 || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9')
	}

	text := document.text[:document.used_text]
	offset := common.get_absolute_position(position, text) or_return
	if (offset >= len(text) || !is_ident(text[offset])) &&
	   offset > 0 &&
	   is_ident(text[offset - 1]) {
		offset -= 1
	}
	if offset >= len(text) || !is_ident(text[offset]) {
		return
	}
	for offset > 0 && is_ident(text[offset - 1]) {
		offset -= 1
	}

	sync.mutex_guard(&semantics_store.mutex)

	file := &semantics_store.files[semantics_key(document.fullpath)]
	if file == nil || !semantics_current(file, document) {
		return
	}

	idents := tf.find_idents(file.exported.uses, offset)
	if len(idents) == 0 {
		idents = tf.find_idents(file.exported.definitions, offset)
	}

	s := &file.export.semantics
	chosen: ^tf.Entity
	for x in idents {
		e := &s.entities[x.entity]
		if e.file < 0 && len(idents) > 1 {
			continue
		}
		if chosen != nil && (chosen.file   != e.file ||
		                     chosen.offset != e.offset) {
			return
		}
		chosen = e
	}
	if chosen == nil {
		return
	}

	entity = {
		name   = strings.clone(chosen.name, allocator),
		kind   = chosen.kind,
		pkg    = strings.clone(chosen.pkg, allocator),
		offset = chosen.offset,
		value  = strings.clone(chosen.value, allocator),
		size   = chosen.size,
		align  = chosen.align,
	}
	if chosen.file >= 0 {
		entity.path = strings.clone(s.files[chosen.file], allocator)
	}
	if chosen.type >= 0 {
		entity.type = strings.clone(s.types[chosen.type], allocator)
	}
	return entity, offset, true
}

semantics_definition :: proc(document: ^Document, position: common.Position) -> (location: common.Location, ok: bool) {
	entity, _, found := semantics_entity_at(document, position)
	if !found || entity.path == "" {
		return
	}
	text := semantics_file_text(entity.path) or_return
	location.uri = common.create_uri(entity.path, context.temp_allocator).uri
	location.range = semantics_range(text, entity.offset, entity.name)
	return location, true
}

semantics_hover :: proc(document: ^Document, entity: Semantic_Entity, start: int, config: ^common.Config) -> Hover {
	name := entity.name
	if entity.pkg != "" {
		name = fmt.tprintf("%s.%s", entity.pkg, entity.name)
	}

	info := name
	#partial switch entity.kind {
	case .Constant:
		if entity.value != "" {
			info = fmt.tprintf("%s :: %s", name, entity.value)
		} else if entity.type != "" {
			info = fmt.tprintf("%s: %s", name, entity.type)
		}
	case .Type, .Procedure, .Group:
		if entity.type != "" {
			info = fmt.tprintf("%s :: %s", name, entity.type)
		}
	case:
		if entity.type != "" {
			info = fmt.tprintf("%s: %s", name, entity.type)
		}
	}
	if config.enable_hover_layout && entity.align > 0 {
		info = append_first_line_comment(info, fmt.tprintf("size=%v, align=%v", entity.size, entity.align))
	}

	return Hover {
		contents = build_markup_content(info, ""),
		range = semantics_range(document.text[:document.used_text], start, entity.name),
	}
}

@(private = "file")
semantics_file_text :: proc(path: string) -> ([]u8, bool) {
	key := semantics_key(path)
	for _, &document in document_storage.documents {
		if !document.client_owned || semantics_key(document.fullpath) != key {
			continue
		}

		sync.mutex_guard(&semantics_store.mutex)

		file := &semantics_store.files[key]
		if file != nil && !semantics_current(file, &document) {
			return nil, false
		}
		return document.text[:document.used_text], true
	}
	data, err := os.read_entire_file(path, context.temp_allocator)
	return data, err == nil
}

@(private = "file")
semantics_range :: proc(text: []u8, offset: int, name: string) -> (range: common.Range) {
	range.start = common.get_relative_token_position(offset, text, 0)
	range.end = range.start
	range.end.character += common.get_character_offset_u8_to_u16(len(name), transmute([]u8)name)
	return
}
