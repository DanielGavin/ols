//! the pdb string name table. reference: https://github.com/willglynn/pdb/blob/master/src/strings.rs
package pdb
import "core:log"

NamesStreamHeader :: struct #packed {
    magic       : u32le, // == NamesStream_HeaderMagic
    hashVersion : NamesStreamHashVersion,
    size        : u32le, // size of all names in bytes
}
NamesStreamHashVersion :: enum u32le {LongHash = 1, LongHashV2 = 2,}
NamesStream_HeaderMagic :u32le: 0xeffe_effe
NamesStream_StartOffset :: size_of(NamesStreamHeader)

parse_names_stream :: proc(this: ^BlocksReader) -> (header: NamesStreamHeader) {
    header = readv(this, NamesStreamHeader)
    if header.magic != NamesStream_HeaderMagic {
        log.warnf("Unrecognized magic 0x%x for pdbNaming table..", header.magic)
    }
    if NamesStream_StartOffset + uint(header.size) > this.size {
        log.warnf("data buffer not big enough, should be %v but was %v", NamesStream_StartOffset + uint(header.size), this.size)
    }
    return
}

// TODO: reverse has stuff
