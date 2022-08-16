//! the pdb info stream, reference: https://llvm.org/docs/PDB/PdbStream.html
package pdb
import "core:log"
import "core:strings"

PdbStream_Index :MsfStreamIdx: 1
NamesStream_Name :: "/names"

PdbStreamHeader :: struct #packed {
    version     : PdbStreamVersion,
    signature   : u32le,
    age         : u32le,
    guid        : u128le,
}

PdbStreamVersion :: enum u32le {
    VC2 = 19941610,
    VC4 = 19950623,
    VC41 = 19950814,
    VC50 = 19960307,
    VC98 = 19970604,
    VC70Dep = 19990604,
    VC70 = 20000404,
    VC80 = 20030901,
    VC110 = 20091201,
    VC140 = 20140508,
}

PdbNamedStreamMap :: struct {
    strBuf : []byte, names : []PdbNamedStream,
}
find_named_stream :: proc(using this: PdbNamedStreamMap, name: string) -> (streamIdx: MsfStreamIdx) {
    for ns in names {
        if strings.compare(ns.name, name) == 0 {
            return MsfStreamIdx(ns.streamIdx)
        }
    }
    return MsfStreamIdx_Invalid
}

PdbNamedStream :: struct {
    name : string, streamIdx : u32le, //?
}

PdbRaw_FeatureSig :: enum u32le {
    None = 0, //?
    VC110 = 20091201,
    VC140 = 20140508,
    NoTypeMerge = 0x4D544F4E,
    MinimalDebugInfo = 0x494E494D,
}

parse_pdb_stream :: proc(this: ^BlocksReader) -> (header: PdbStreamHeader, nameMap: PdbNamedStreamMap, features: []PdbRaw_FeatureSig) {
    header = readv(this, PdbStreamHeader)
    if header.version != .VC70 {
        log.warnf("unrecoginized pdbStreamVersion: %v", header.version)
    }

    nameStringLen := readv(this, u32le)
    //log.debugf("nameStringLen: %v", nameStringLen)
    nameMap.strBuf = read_packed_array(this, uint(nameStringLen), byte)
    namesTable := read_hash_table(this, u32le)
    nameMap.names = make([]PdbNamedStream, namesTable.size)
    nameIdx := 0
    for i in 0..< namesTable.capacity {
        kv, ok := get_kv_at(&namesTable, i)
        if ok {
            //fmt.printf("k: %v, v: %v, vstr: %v\n", kv.key, kv.value, ))
            nameStr : string
            assert(kv.key < nameStringLen, "invalid name key")
            nameStr = strings.string_from_nul_terminated_ptr(&nameMap.strBuf[kv.key], len(nameMap.strBuf)-int(kv.key))
            //fmt.printf("bucket#%v [%v:%v], name: %v\n", i, kv.key, kv.value, nameStr)
            nameMap.names[nameIdx] = {nameStr, kv.value }
            nameIdx+=1
        }
    }

    featuresLen := (this.size - this.offset)/size_of(PdbRaw_FeatureSig)
    features = read_packed_array(this, uint(featuresLen), PdbRaw_FeatureSig)

    return
}
