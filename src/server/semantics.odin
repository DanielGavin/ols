package server

import "base:runtime"
import "core:log"
import "core:mem/virtual"
import tf "core:odin/tool-format"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

Semantics_Store :: struct {
	mutex: sync.Mutex,
	files: map[string]Semantics_File, // by `semantics_key`
}

Semantics_File :: struct {
	export:   ^Semantics_Export,
	exported: ^tf.Exported_File,
	version:  Maybe(int),
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
