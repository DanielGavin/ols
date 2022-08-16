//! tpi or ipi stream, reference: https://llvm.org/docs/PDB/TpiStream.html
package pdb
import "core:log"

TpiStream_Index :MsfStreamIdx: 2
IpiStream_Index :MsfStreamIdx: 4

TpiStreamHeader :: struct #packed {
    version             : TpiStreamVersion, // appears to always be v80
    headerSize          : u32le, // == sizeof(TpiStreamHeader)
    typeIndexBegin      : TypeIndex, // usually 0x1000(4096), type indices lower are usually reserved
    typeIndexEnd        : TypeIndex, // total number of type records = typeIndexEnd-typeIndexBegin
    typeRecordBytes     : u32le, // type record data size following the header

    hashStreamIndex     : MsfStreamIdx, // -1 means not present, usually always observed to be present
    hashAuxStreamIndex  : MsfStreamIdx, // unclear what for
    hashKeySize         : u32le, // usually 4 bytes
    numHashBuckets      : u32le, // number of buckets used to generate these hash values

    // ?offset and size within the hash stream. HashBufferLength should == numTypeRecords * hashKeySize
    hashValueBufferOffset, hashValueBufferLength: i32le,
    // type index offset buffer pos within the hash stream, which is
    // a list of u32le (typeIndex, offset in type record data)pairs that can be biSearched
    indexOffsetBufferOffset, indexOffsetBufferLength: i32le,
    // a pdb hashTable, with u32le (hash values, type indices) kv pair
    hashAdjBufferOffset, hashAdjBufferLength: i32le,
}

TpiStreamVersion :: enum u32le {
    V40 = 19950410,
    V41 = 19951122,
    V50 = 19961031,
    V70 = 19990903,
    V80 = 20040203,
}

TpiIndexOffsetBuffer :: struct {
    buf : []TpiIndexOffsetPair,
}
TpiIndexOffsetPair :: struct #packed {ti: TypeIndex, offset: u32le,}

seek_for_tpi :: proc(using this: TpiIndexOffsetBuffer, ti : TypeIndex, tpiStream: ^BlocksReader) -> (ok: bool) {
    // bisearch then linear seaarch proc
    lo, hi := 0, (len(buf)-1)
    if hi < 0 || buf[lo].ti > ti || buf[hi].ti < ti do return false
    // ti in range, do a bisearch
    for lo <= hi {
        //log.debugf("Find block [%v, %v) for ti%v", lo,hi, ti)
        mid := lo + ((hi-lo)>>1)
        mv := buf[mid].ti
        if mv == ti {
            lo = mid + 1
            break
        }
        else if mv > ti do hi = mid - 1
        else do lo = mid + 1
    }
    if lo > 0 do lo -= 1
    //log.debugf("Find block [%v, %v) for ti%v", lo,lo+1, ti)
    // now a linear search from lo to high
    tIdx := buf[lo].ti
    tpiStream.offset = cast(uint)buf[lo].offset
    endOffset := tpiStream.size
    if lo+1 < len(buf) do endOffset = cast(uint)buf[lo+1].offset
    for ;tpiStream.offset < endOffset && tIdx != ti; tIdx+=1 {
        cvtHeader := readv(tpiStream, CvtRecordHeader)
        tpiStream.offset += cast(uint)cvtHeader.length - size_of(CvtRecordKind)
    }
    //log.debugf("Block offset: %v", tpiStream.offset)
    return true
}

parse_tpi_stream :: proc(this: ^BlocksReader, dir: ^StreamDirectory) -> (header: TpiStreamHeader, tiob: TpiIndexOffsetBuffer) {
    header = readv(this, TpiStreamHeader)
    assert(header.headerSize == size_of(TpiStreamHeader), "Incorrect header size, mulfunctional stream")
    if header.version != .V80 {
        log.warnf("unrecoginized tpiVersion: %v", header.version)
    }

    if header.hashStreamIndex >= 0 {
        hashStream := get_stream_reader(dir, header.hashStreamIndex)
        iobLen := header.indexOffsetBufferLength / size_of(TpiIndexOffsetPair)
        tiob.buf = make([]TpiIndexOffsetPair, iobLen)
        hashStream.offset = uint(header.indexOffsetBufferOffset) //?
        for i in 0..<iobLen {
            tiob.buf[i] = readv(&hashStream, TpiIndexOffsetPair)
            tiob.buf[i].offset += u32le(this.offset) // apply header offset here as well.
        }
    } else {
        // fallback
        tiob.buf = make([]TpiIndexOffsetPair, 1)
        tiob.buf[0] = TpiIndexOffsetPair{ti = header.typeIndexBegin}
    }
    return
}
