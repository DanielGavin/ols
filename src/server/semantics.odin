package server

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem/virtual"
import tf "core:odin/tool-format"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:time"
import "core:unicode/utf8"

import "src:common"

Semantics_Store :: struct {
	mutex:            sync.Mutex,
	files:            map[string]Semantics_File, // by `semantics_key`
	covers_workspace: bool,                      // a workspace check has been loaded in full, so no workspace file is missing
	unparsed:         map[string]string,         // by `semantics_key`: the files of checked packages that were not parsed, e.g. for other targets or tests
}

Semantics_File :: struct {
	export:   ^Semantics_Export,
	exported: ^tf.Exported_File,
	version:  Maybe(int), // The version of the open document whose text was checked, and `nil` indicates it was checked from disk

	// When checked from disk (version == nil), the last version of the open document compared with the disk and whether they matched
	compared: Maybe(int),
	matches:  bool,

	modified: time.Time,
}

@(private = "file")
semantics_unmodified :: proc(file: ^Semantics_File) -> bool {
	if file.version != nil {
		return false
	}
	modified, err := os.modification_time_by_path(file.export.semantics.files[file.exported.file])
	return err == nil && modified == file.modified
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

load_semantics :: proc(paths: []string, buffers: []Check_Buffer, workspace: bool) {
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
	loaded_all := true
	for path in paths {
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil {
			loaded_all = false
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
			loaded_all = false
			continue
		}

		modified := make([]time.Time, len(export.semantics.exported), context.temp_allocator)
		for exported, i in export.semantics.exported {
			modified[i], _ = os.modification_time_by_path(export.semantics.files[exported.file])
		}


		exported_keys := make(map[string]bool, len(export.semantics.exported), context.temp_allocator)
		dirs          := make(map[string]bool, 16, context.temp_allocator)

		for exported in export.semantics.exported {
			exported_path := export.semantics.files[exported.file]
			exported_keys[semantics_key(exported_path)] = true
			if slash := strings.last_index_byte(exported_path, '/'); slash >= 0 {
				dirs[exported_path[:slash]] = true
			}
		}

		unparsed := make([dynamic]string, context.temp_allocator)
		for dir in dirs {
			infos := os.read_all_directory_by_path(dir, context.temp_allocator) or_continue

			for info in infos {
				file_path := fmt.tprintf("%s/%s", dir, info.name)
				if info.type == .Regular &&
				   strings.has_suffix(info.name, ".odin") &&
				   !exported_keys[semantics_key(file_path)] {
					append(&unparsed, file_path)
				}
			}
		}

		sync.mutex_lock(&semantics_store.mutex)
		if semantics_store.files == nil {
			semantics_store.files = make(map[string]Semantics_File, 1024, runtime.heap_allocator())
			semantics_store.unparsed = make(map[string]string, 64, runtime.heap_allocator())
		}

		stale := make([dynamic]string, context.temp_allocator)
		for key, value in semantics_store.unparsed {
			slash := strings.last_index_byte(value, '/')
			if slash >= 0 && value[:slash] in dirs {
				append(&stale, key)
			}
		}

		for key in stale {
			old_key, old_value := delete_key(&semantics_store.unparsed, key)
			delete(old_key, runtime.heap_allocator())
			delete(old_value, runtime.heap_allocator())
		}

		for file_path in unparsed {
			key := semantics_key(file_path, runtime.heap_allocator())
			semantics_store.unparsed[key] = strings.clone(file_path, runtime.heap_allocator())
		}

		for &exported, i in export.semantics.exported {
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
				modified = modified[i],
			}
			export.files += 1
		}

		if workspace && loaded_all && path == paths[len(paths) - 1] {
			semantics_store.covers_workspace = true
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

@(private = "file")
is_ident :: proc(c: u8) -> bool {
	// TODO(bill): This is not technically correct because it's pretending anything non-ascii is correct
	// but this is probably more than enough in practice
	switch c {
	case '_',
	     0x80..=0xff,
	     'a'..='z',
	     'A'..='Z',
	     '0'..='9':
		return true
	}
	return false
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

	if chosen == nil && len(idents) == 0 {
		for &e in s.entities {
			// TODO(bill): remove once the compiler records local variables as definitions
			if e.offset == offset &&
			   e.file   == file.exported.file &&
			   is_ident_at(text, offset, e.name) {
				chosen = &e
				break
			}
		}
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

	sync.mutex_guard(&semantics_store.mutex)
	if file := &semantics_store.files[key]; file != nil && !semantics_unmodified(file) {
		return nil, false
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

semantics_references :: proc(
	document: ^Document,
	position: common.Position,
	current_file_only: bool,
	include_declaration: bool,
) -> (
	locations: []common.Location,
	ok: bool,
) {
	entity, _ := semantics_entity_at(document, position) or_return
	if entity.path == "" {
		return
	}

	open := make(map[string]^Document, len(document_storage.documents), context.temp_allocator)
	for _, &d in document_storage.documents {
		if d.client_owned {
			open[semantics_key(d.fullpath)] = &d
		}
	}

	current_key   := semantics_key(document.fullpath)
	declaring_key := semantics_key(entity.path)

	local := entity.pkg == "" && entity.kind in bit_set[tf.Entity_Kind]{.Parameter, .Variable, .Type, .Label, .Import, .Library}

	sync.mutex_guard(&semantics_store.mutex)
	if !current_file_only && !local && !semantics_store.covers_workspace {
		return
	}

	declarations := make(map[^Semantics_Export][]bool, 16, context.temp_allocator)
	result       := make([dynamic]common.Location,         context.temp_allocator)
	offsets      := make([dynamic]int,                     context.temp_allocator)
	ranges       := make([dynamic]common.Range,            context.temp_allocator)

	for key, &file in semantics_store.files {
		if (current_file_only && key != current_key) || (local && key != declaring_key) {
			continue
		}

		s := &file.export.semantics
		is_declaration, marked := declarations[file.export]
		if !marked {
			is_declaration = make([]bool, len(s.entities), context.temp_allocator)
			for e, i in s.entities {
				is_declaration[i] = e.offset == entity.offset && e.name == entity.name && e.file >= 0 && semantics_key(s.files[e.file]) == declaring_key
			}
			declarations[file.export] = is_declaration
		}

		clear(&offsets)
		for i := 0; i+1 < len(file.exported.uses); i += 2 {
			if is_declaration[file.exported.uses[i+1]] {
				append(&offsets, int(file.exported.uses[i]))
			}
		}

		if include_declaration && key == declaring_key {
			append(&offsets, entity.offset)
		}

		if len(offsets) == 0 && len(file.exported.inactive) == 0 {
			continue
		}

		// the offsets are into the text that was checked, which must still be the text
		path := s.files[file.exported.file]
		text: []u8
		if d, is_open := open[key]; is_open {
			semantics_current(&file, d) or_return

			text = d.text[:d.used_text]
		} else {
			semantics_unmodified(&file) or_return

			data, err := os.read_entire_file(path, context.temp_allocator)
			if err != nil {
				return
			}
			text = data
		}

		for i := 0; i + 1 < len(file.exported.inactive); i += 2 {
			if contains_word(string(text[file.exported.inactive[i]:file.exported.inactive[i + 1]]), entity.name) {
				return
			}
		}
		if len(offsets) == 0 {
			continue
		}

		slice.sort(offsets[:])

		clear(&ranges)
		semantics_ranges(text, offsets[:], entity.name, &ranges)

		uri := common.create_uri(path, context.temp_allocator).uri
		for range in ranges {
			append(&result, common.Location{uri = uri, range = range})
		}
	}

	// a declaration the checks did not export, such as one in `core`
	if include_declaration && declaring_key not_in semantics_store.files && (!current_file_only || declaring_key == current_key) {
		text: []u8
		if d, is_open := open[declaring_key]; is_open {
			text = d.text[:d.used_text]
		} else {
			data, err := os.read_entire_file(entity.path, context.temp_allocator)
			if err != nil {
				return
			}
			text = data
		}
		clear(&ranges)
		semantics_ranges(text, []int{entity.offset}, entity.name, &ranges)
		uri := common.create_uri(entity.path, context.temp_allocator).uri
		for range in ranges {
			append(&result, common.Location{uri = uri, range = range})
		}
	}

	if !current_file_only && !local {
		for key, path in semantics_store.unparsed {
			text: []u8
			if d, is_open := open[key]; is_open {
				text = d.text[:d.used_text]
			} else {
				data, err := os.read_entire_file(path, context.temp_allocator)
				if err != nil {
					continue
				}
				text = data
			}
			if contains_word(string(text), entity.name) {
				return
			}
		}
	}
	return result[:], true
}

@(private = "file")
contains_word :: proc(text, word: string) -> bool {
	for start := 0; start < len(text); /**/ {
		i := strings.index(text[start:], word)
		if i < 0 {
			return false
		}
		i += start
		end := i + len(word)
		if (i == 0 || !is_ident(text[i - 1])) && (end >= len(text) || !is_ident(text[end])) {
			return true
		}
		start = i + 1
	}
	return false
}

// Whether `text` has the identifier `name` at `offset`, rather than a longer one
@(private = "file")
is_ident_at :: proc(text: []u8, offset: int, name: string) -> bool {
	end := offset + len(name)
	if offset < 0 {
		return false
	}
	if len(text) < end {
		return false
	}
	if string(text[offset:end]) != name {
		return false
	}
	return end == len(text) || !is_ident(text[end])
}

// The ranges of `name` at the sorted `offsets`, walking `text` once.
// An offset where the text is not `name` is skipped, such as a call through a procedure group, which records the procedure it picks.
@(private = "file")
semantics_ranges :: proc(text: []u8, offsets: []int, name: string, ranges: ^[dynamic]common.Range) {
	width := common.get_character_offset_u8_to_u16(len(name), transmute([]u8)name)

	position: common.Position

	at := 0
	for offset, i in offsets {
		if (i > 0 && offset == offsets[i - 1]) || !is_ident_at(text, offset, name) {
			continue
		}
		for at < offset {
			r, w := utf8.decode_rune(text[at:])
			switch {
			case r == '\n':
				position.line += 1
				position.character = 0
			case r >= 0x10000:
				position.character += 2
			case:
				position.character += 1
			}
			at += max(w, 1)
		}
		append(ranges, common.Range{start = position, end = {line = position.line, character = position.character + width}})
	}
}
