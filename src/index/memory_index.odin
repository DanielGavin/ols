package index

import "core:hash"

/*
    This is a in memory index designed for the dynamic indexing of symbols and files.
    Designed for few files and should be fast at rebuilding.

    Right now the implementation is quite naive.
 */
MemoryIndex :: struct {
    collection: SymbolCollection,
};


make_memory_index :: proc(collection: SymbolCollection) -> MemoryIndex {

    return MemoryIndex {
        collection = collection,
    };

}

memory_index_lookup :: proc(index: ^MemoryIndex, id: string) -> (Symbol, bool) {

    hashed := hash.murmur64(transmute([]u8)id);

    return index.collection.symbols[hashed];
}