package server

import "core:fmt"
import "core:hash"
import "core:log"
import "core:slice"
import "core:strings"

import "src:common"

MemoryIndex :: struct {
	collection:        SymbolCollection,
	last_package_name: string,
	last_package:      ^map[string]Symbol,
}

make_memory_index :: proc(collection: SymbolCollection) -> MemoryIndex {
	return MemoryIndex{collection = collection}
}

memory_index_clear_cache :: proc(index: ^MemoryIndex) {
	index.last_package_name = ""
	index.last_package = nil
}

memory_index_lookup :: proc(index: ^MemoryIndex, name: string, pkg: string) -> (Symbol, bool) {
	if index.last_package_name == pkg && index.last_package != nil {
		return index.last_package[name]
	}

	if _pkg, ok := &index.collection.packages[pkg]; ok {
		index.last_package = &_pkg.symbols
		index.last_package_name = pkg
		return _pkg.symbols[name]
	} else {
		index.last_package = nil
		index.last_package_name = ""
	}

	return {}, false
}

score_name :: proc(matchers: []^common.FuzzyMatcher, name: string) -> (f32, bool) {
	score := f32(1)
	for matcher in matchers {
		s, ok := common.fuzzy_match(matcher, name)
		if ok != 1 {
			return 0, false
		}
		score *= s
	}

	return score, true
}

memory_index_fuzzy_search :: proc(
	index: ^MemoryIndex,
	name: string,
	pkgs: []string,
	current_file: string,
	resolve_fields := false,
	limit := 0,
) -> (
	[]FuzzyResult,
	bool,
) {
	symbols := make([dynamic]FuzzyResult, 0, context.temp_allocator)

	fields := strings.fields(name, context.temp_allocator)
	matchers := make([dynamic]^common.FuzzyMatcher, 0, len(fields), context.temp_allocator)
	for field in fields {
		append(&matchers, common.make_fuzzy_matcher(field))
	}

	top := 100
	current_pkg := get_package_from_filepath(current_file)

	for pkg in pkgs {
		if pkg, ok := index.collection.packages[pkg]; ok {
			for _, symbol in pkg.symbols {
				if should_skip_private_symbol(symbol, current_pkg, current_file) {
					continue
				}
				if resolve_fields {
					// TODO: this only does the top level fields, we may want to travers all the way down in the future
					#partial switch v in symbol.value {
					case SymbolStructValue:
						for name, i in v.names {
							full_name := fmt.tprintf("%s.%s", symbol.name, name)
							if score, ok := score_name(matchers[:], full_name); ok {
								s := symbol
								construct_struct_field_symbol(&s, symbol.name, v, i)
								s.name = full_name
								result := FuzzyResult {
									symbol = s,
									score  = score,
								}

								append(&symbols, result)
							}
						}
					case SymbolBitFieldValue:
						for name, i in v.names {
							full_name := fmt.tprintf("%s.%s", symbol.name, name)
							if score, ok := score_name(matchers[:], full_name); ok {
								s := symbol
								construct_bit_field_field_symbol(&s, symbol.name, v, i)
								s.name = full_name
								result := FuzzyResult {
									symbol = s,
									score  = score,
								}

								append(&symbols, result)
							}
						}
					case SymbolGenericValue:
						for name, i in v.field_names {
							full_name := fmt.tprintf("%s.%s", symbol.name, name)
							if score, ok := score_name(matchers[:], full_name); ok {
								s := symbol
								s.name = full_name
								s.type = .Field
								s.range = v.ranges[i]
								result := FuzzyResult {
									symbol = s,
									score  = score,
								}

								append(&symbols, result)
							}
						}
					}
				}
				if score, ok := score_name(matchers[:], symbol.name); ok {
					result := FuzzyResult {
						symbol = symbol,
						score  = score,
					}

					append(&symbols, result)
				}
			}
		}
	}

	slice.sort_by(symbols[:], proc(i, j: FuzzyResult) -> bool {
		return j.score < i.score
	})

	if limit > 0 {
		return symbols[:min(limit, len(symbols))], true
	} else if name == "" {
		return symbols[:], true
	} else {
		return symbols[:min(top, len(symbols))], true
	}
}
