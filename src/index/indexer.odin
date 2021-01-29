package index

import "core:odin/ast"
import "core:fmt"
import "core:strings"
import "core:log"
import "core:sort"


/*
    Concept ideas:

    static indexing:

    is responsible for implementing the indexing of symbols for static files.

    This is to solve the scaling problem of large projects with many files and symbols, as most of these files will be static.

    Possible scopes for static files:
    global scope (we don't have hiarachy of namespaces and therefore only need to look at the global scope)

    Scopes not part of the indexer:
    function scope, file scope, package scope(these are only relevant for dynamic active files in your project, that use the ast instead of indexing)

    Potential features:
        Allow for saving the indexer, instead of recreating it everytime the lsp starts(but you would have to account for stale data).


    dynamic indexing:

    When the user modifies files we need some smaller index to handle everything the user is using right now. This will allow
    us to rebuild parts of the index without too much of a performance hit.

    This index is first searched and if nothing is found look in the static index.
 */


Indexer :: struct {
    built_in_packages: [dynamic] string,
    static_index: MemoryIndex,
    dynamic_index: MemoryIndex,
};

indexer: Indexer;

FuzzyResult :: struct {
    symbol: Symbol,
    score: f32,
};


lookup :: proc(name: string, pkg: string, loc := #caller_location) -> (Symbol, bool) {

    if symbol, ok := memory_index_lookup(&indexer.dynamic_index, name, pkg); ok {
        log.infof("lookup dynamic name: %v pkg: %v, symbol %v location %v", name, pkg, symbol, loc);
        return symbol, true;
    }

    if symbol, ok := memory_index_lookup(&indexer.static_index, name, pkg); ok {
        log.infof("lookup name: %v pkg: %v, symbol %v location %v", name, pkg, symbol, loc);
        return symbol, true;
    }

    for built in indexer.built_in_packages {

        if symbol, ok := memory_index_lookup(&indexer.static_index, name, built); ok {
            log.infof("lookup name: %v pkg: %v, symbol %v location %v", name, pkg, symbol, loc);
            return symbol, true;
        }

    }

    log.infof("lookup failed name: %v pkg: %v location %v", name, pkg, loc);
    return {}, false;
}


fuzzy_search :: proc(name: string, pkgs: [] string) -> ([] FuzzyResult, bool) {
    dynamic_results, dynamic_ok := memory_index_fuzzy_search(&indexer.dynamic_index, name, pkgs);
    index_results, static_ok := memory_index_fuzzy_search(&indexer.static_index, name, pkgs);
    result := make([dynamic] FuzzyResult, context.temp_allocator);

    if !dynamic_ok || !static_ok {
        return {}, false;
    }

    for r in dynamic_results {
        append(&result, r);
    }

    for r in index_results {
        append(&result, r);
    }

    sort.sort(fuzzy_sort_interface(&result));

    name := "";
    pkg := "";

    for r, i in result {
        if name == r.symbol.name && pkg == r.symbol.pkg {
            ordered_remove(&result, i);
        }

        name = r.symbol.name;
        pkg = r.symbol.pkg;
    }

    return result[:], true;
}


fuzzy_sort_interface :: proc(s: ^[dynamic] FuzzyResult) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(s),
		len = proc(it: sort.Interface) -> int {
			s := (^[dynamic] FuzzyResult)(it.collection);
			return len(s^);
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			s := (^[dynamic] FuzzyResult)(it.collection);
			return s[i].score > s[j].score;
		},
		swap = proc(it: sort.Interface, i, j: int) {
			s := (^[dynamic] FuzzyResult)(it.collection);
			s[i], s[j] = s[j], s[i];
		},
	};
}
