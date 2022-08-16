//! https://llvm.org/docs/PDB/HashTable.html
package pdb

PdbHashTable :: struct($Value: typeid) {
    size: u32le,
    capacity: u32le,
    presentBits: BitVector,
    deletedBits: BitVector,
    kvPairs: []PdbHashTable_KVPair(Value),
}

PdbHashTable_KVPair :: struct($Value: typeid) #packed {
    key: u32le, value: Value,
}

BitVector :: struct {
    //wordCount : u32le,
    words: []u32le,
}

get_kv_at :: proc(using this: ^PdbHashTable($T), at: u32le) -> (ret:PdbHashTable_KVPair(T), ok:bool) {
    ok = get_bit(&presentBits, at)
    if !ok {
        ret = {}
        return
    }
    ret = kvPairs[at]
    return
}

get_bit :: proc(using this: ^BitVector, at: u32le) -> bool {
    ELEMENT_PER_WORD :: 32
    wi := at / ELEMENT_PER_WORD
    if int(wi) >= len(words) do return false
    word := words[uint(wi)]
    iiw := at - (wi * ELEMENT_PER_WORD)
    return (word & (1 << iiw)) != 0
}

read_hash_table :: proc(using this: ^BlocksReader, $Value: typeid) -> (ret:PdbHashTable(Value)) {
    ret.size = readv(this, u32le)
    ret.capacity = readv(this, u32le)
    //log.debugf("hash_table size%v capacity%v", ret.size, ret.capacity)
    ret.presentBits = read_bit_vector(this)
    //log.debugf("presentBits: %v words read: 0x%x", len(ret.presentBits.words), ret.presentBits.words)
    ret.deletedBits = read_bit_vector(this)
    //log.debugf("deletedBit: %v words read: 0x%x", len(ret.deletedBits.words), ret.deletedBits.words)
    ret.kvPairs = make([]PdbHashTable_KVPair(Value), ret.capacity)
    for i in 0..<ret.capacity {
        //NOTE(lux): documentation given at https://llvm.org/docs/PDB/HashTable.html doesn't seems to match actual pdbs tested, so we're guessing here that only valid and tombstone blocks get written into the file
        if get_bit(&ret.presentBits, i) || get_bit(&ret.deletedBits, i) {
            //log.debugf("read kvPair#%v of type %v with size %v... ", i, typeid_of(Value), size_of(PdbHashTable_KVPair(Value)))
            ret.kvPairs[i] = readv(this, PdbHashTable_KVPair(Value))
            //log.debugf("key: %v, value: %v", ret.kvPairs[i].key, ret.kvPairs[i].value)
        }
    }
    return
}

read_bit_vector :: proc(using this: ^BlocksReader) -> (ret: BitVector) {
    wordCount := readv(this, u32le)
    ret.words = read_packed_array(this, uint(wordCount), u32le)
    return
}
