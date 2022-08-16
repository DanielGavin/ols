//! reference: https://llvm.org/docs/PDB/MsfFile.html https://llvm.org/docs/PDB/index.html
package pdb
import "core:strings"
import "core:mem"
import "core:log"
import "core:intrinsics"
import "core:runtime"
import "core:io"

// SuperBlock|FPM1|FPM2|DataBlocks[BlockSize-3]|FPM1|FPM2|DataBlocks[BlockSize-3])+

FileMagic :string: "Microsoft C/C++ MSF 7.00\r\n\x1a\x44\x53\x00\x00\x00"
SuperBlock :: struct #packed {
    //fileMagic : [len(SuperBlock_FileMagic)]byte, // == SuperBlock_FileMagic
    blockSize : u32le, // block size of the internal file system == 4096
    freeBlockMapBlock : u32le, // index of a block which contains a bitfield indicating free blocks in the file. This index can only be 1/2. ????A file has two FPM to support incremental and atomic updates of the underlying MSF file: while writing, if active FPM is 1, you can write to free blocks indicated by FPM2, and vice-versa.??????
    numBlocks : u32le, // total number of blocks in file, NumBlocks * BlockSize should == size of the file on disk
    numDirectoryBytes : u32le, // size of the StreamDirectory
    unknown : u32le,
    blockMapAddr: u32le, // index of a block within the MSF file, which stores an array of u32le, listing the blocks that the stream directory resides on, because the stream directory might occupy more than one block. array length given by ceil(NumDirectoryBytes/blockSize)
}

// root to other streams in an MSF file, total bytes occupied by this struct in file is stored in superBlock.numDirectoryBytes
StreamDirectory :: struct {
    numStreams : u32le,
    streamSizes : []u32le, // len == numStreams. size of each stream in bytes
    streamBlocks : [][]u32le, // blockIndices = StreamBlocks[streamIdx]. len(blockIndices) == ceil(streamSizes[streamIdx]/superBlock.blockSize)
    r : io.Reader,
    blockSize: u32le,
}
MsfStreamIdx :: distinct u16le
MsfStreamIdx_Invalid : MsfStreamIdx : 0xffff
stream_idx_valid ::#force_inline proc(idx: MsfStreamIdx) -> bool {return idx < MsfStreamIdx_Invalid}

get_stream_reader :: #force_inline proc(using this: ^StreamDirectory, streamIdx : MsfStreamIdx) -> BlocksReader {
    assert(stream_idx_valid(streamIdx))
    return make_reader_from_indiced_buf(r, streamBlocks[streamIdx], int(blockSize), streamSizes[streamIdx])
}

read_superblock :: proc(r: io.Reader) -> (this : SuperBlock, success: bool) {
    SuperBlock_ReadSize :: len(FileMagic) + size_of(SuperBlock)
    success = false
    if r->impl_size() < SuperBlock_ReadSize {
        log.debug("stream len too small to be a valid pdb file")
        return
    }
    data: [SuperBlock_ReadSize]byte
    if nRead, err := io.read(r, data[:]); err != nil || nRead != len(data) {
        log.debugf("stream read failed with %v, nRead:%d", err, nRead)
        return
    }
    if strings.compare(strings.string_from_ptr(&data[0], len(FileMagic)), FileMagic) != 0 {
        log.debug("FileMagic mismatch")
        return
    }

    this = (cast(^SuperBlock)&data[len(FileMagic)])^
    success = true
    return
}

read_stream_dir :: proc(using this: ^SuperBlock, r: io.Reader) -> (sd: StreamDirectory, success: bool) {
    success = false
    if seekN, seekErr := r->impl_seek(i64(blockMapAddr * blockSize), .Start); seekErr != nil {
        log.debugf("seek failed with %v", seekErr)
        return
    }
    sdBlockCount := ceil_div(numDirectoryBytes, blockSize)
    iData := make([]byte, sdBlockCount*size_of(u32le), context.temp_allocator)
    defer delete(iData, context.temp_allocator)
    if nRead, readErr := r->impl_read(iData); readErr != nil || nRead != len(iData) {
        log.debugf("read block map failed with %v, nRead: %d, should be %d", readErr, nRead, numDirectoryBytes)
        return
    }
    breader := make_reader_from_indiced_buf(r, transmute([]u32le)mem.Raw_Slice{&iData[0], int(sdBlockCount)}, int(blockSize), numDirectoryBytes)

    sd.numStreams = readv(&breader, u32le)
    //fmt.printf("number of streams %v\n", sd.numStreams)
    sd.streamSizes = make([]u32le, sd.numStreams)
    sd.streamBlocks = make([][]u32le, sd.numStreams)
    sd.r = r
    sd.blockSize = blockSize
    for i in 0..<sd.numStreams {
        sd.streamSizes[i] = readv(&breader, u32le)
        if sd.streamSizes[i] == 0xffff_ffff {
            sd.streamSizes[i] = 0 //? clear invalid streamSizes?
        }
        //fmt.printf("reading stream#%v size %v\n", i, sd.streamSizes[i])
        sd.streamBlocks[i] = make([]u32le, ceil_div(sd.streamSizes[i], blockSize))
    }
    
    for i in 0..<sd.numStreams {
        streamBlock := sd.streamBlocks[i]
        //fmt.printf("reading stream#%v indices...\n", i)
        for j in 0..< len(streamBlock) {
            streamBlock[j] = readv(&breader, u32le)
        }
    }
    success = true
    return
}

find_stream_dir :: proc(r: io.Reader) -> (sd: StreamDirectory, success: bool) {
    success = false
    pdbContent := read_superblock(r) or_return
    sd = read_stream_dir(&pdbContent, r) or_return
    success = true
    return
}

//@private
BlocksReader :: struct {
    data: []byte,
    offset : uint,
    size : uint,
}
_dummy_indices :[]u32le = {0,}
make_dummy_reader :: proc(data: []byte) -> BlocksReader {
    return BlocksReader{
        data = data,
        offset = 0,
        size = len(data),
    }
}
make_reader_from_indiced_buf :: proc(r: io.Reader, indices: []u32le, blockSize: int, totalSize: u32le) -> BlocksReader {
    buf := make([]byte, cast(uint)totalSize)
    for i in 0..<len(indices)-1 {
        isrc := int(indices[i])*blockSize
        r->impl_seek(i64(isrc), .Start)
        r->impl_read(buf[i*blockSize:(i+1)*blockSize])
    }
    if len(indices) > 0 { // last buf
        i := len(indices) - 1
        isrc := int(indices[i])*blockSize
        r->impl_seek(i64(isrc), .Start)
        r->impl_read(buf[i*blockSize:])
    }
    return make_dummy_reader(buf)
}

@private
_can_read_packed :: proc ($T: typeid) -> bool {
    if intrinsics.type_is_struct(T) {
        bti := runtime.type_info_base(type_info_of(T))
        ti, ok := bti.variant.(runtime.Type_Info_Struct)
        if !ok do return false
        return ti.is_packed
    }
    return true
}

MsfNotPackedMarker :: struct {} // we use this marker to bypass the lacking of `intrinsics.is_struct_packed()` in certain cases

read_packed_from_stream :: #force_inline proc(r: io.Stream, $T: typeid) -> (ret:T, err:io.Error) {
    when ODIN_DEBUG==true {
        if (!_can_read_packed(T))  {
            log.errorf("Invalid type: %v", type_info_of(T).variant)
            assert(false)
        }
    }
    buf := transmute([]byte)mem.Raw_Slice{&ret, size_of(T),}
    r->impl_read(buf) or_return
    return ret, err
}

read_packed_array :: proc(using this: ^BlocksReader, count: uint, $T: typeid) -> (ret: []T) {
    when ODIN_DEBUG==true {
        if (!_can_read_packed(T))  {
            log.errorf("Invalid type: %v", type_info_of(T).variant)
            assert(false)
        }
    }
    endOffset := offset + count * size_of(T)
    assert(endOffset <= this.size)
    defer offset = endOffset
    return mem.slice_ptr(cast(^T)&data[offset], int(count))
}

read_packed :: #force_inline proc(using this: ^BlocksReader, $T: typeid) -> (ret: T)
    where !intrinsics.type_has_field(T, "_base"),
          !intrinsics.type_is_subtype_of(T, MsfNotPackedMarker) {
        when ODIN_DEBUG==true {
            if (!_can_read_packed(T))  {
                log.errorf("Invalid type: %v", type_info_of(T).variant)
                assert(false)
            }
        }    
        tsize := size_of(T)
        assert(size == 0 || offset + uint(tsize) <= size, "block overflow")
        pret := cast(^byte)&ret
        psrc := &data[offset]
        mem.copy_non_overlapping(pret, psrc, tsize)
        offset += uint(tsize)
        return
}

read_with_trailing_name :: #force_inline proc(this: ^BlocksReader, $T: typeid) -> (ret: T)
    where intrinsics.type_has_field(T, "_base"), 
          intrinsics.type_has_field(T, "name"),
          intrinsics.type_field_index_of(T, "name") == 1,
          intrinsics.type_struct_field_count(T) == 2 {
    ret._base = read_packed(this, type_of(ret._base))
    ret.name = read_length_prefixed_name(this)
    return ret
}

read_with_size_and_trailing_name :: #force_inline proc(this: ^BlocksReader, $T: typeid) -> (ret: T)
    where intrinsics.type_has_field(T, "_base"), 
          intrinsics.type_has_field(T, "name"),
          intrinsics.type_has_field(T, "size"),
          intrinsics.type_field_index_of(T, "size") == 1,
          intrinsics.type_field_index_of(T, "name") == 2,
          intrinsics.type_struct_field_count(T) == 3 {
    ret._base = read_packed(this, type_of(ret._base))
    ret.size = cast(uint)read_int_record(this)
    ret.name = read_length_prefixed_name(this)
    return
}

readv :: proc { read_packed, read_with_trailing_name, read_with_size_and_trailing_name, read_with_trailing_rag, read_cvtBuildInfo, read_cvtUnion, read_cvtfArgList, read_cvtfBclass, read_cvtfVbclass, read_cvtfMember, read_cvtfEnumerate, read_cvtFieldList, read_dbiModInfo, read_dbiFileInfos, read_cvsFunctionList, read_cvsInlineSite, }

read_length_prefixed_name :: proc(this: ^BlocksReader) -> (ret: string) {
    //nameLen := cast(int)readv(this, u8) //? this is a fucking lie?
    nameLen :int = 0
    for i in this.offset..<this.size {
        if this.data[i] == 0 do break
        nameLen+=1
    }
    defer this.offset+=uint(nameLen+1) // eat trailing \0 as well
    if nameLen == 0 do return ""
    return strings.string_from_ptr(&this.data[this.offset], nameLen)
}

@private
ceil_div :: #force_inline proc(a: u32le, b: u32le) -> u32le {
    ret := a / b
    if b * ret != a do ret += 1
    return ret
}

@private
Stack :: struct($T: typeid) {
    buf:        []T,
    count:      int,
    allocator:  mem.Allocator,
}
make_slice_clone_from_stack :: #force_inline proc(stack: ^Stack($T)) -> (ret: []T) {
    ret = make([]T, stack.count)
    intrinsics.mem_copy_non_overlapping(&ret[0], &stack.buf[0], stack.count * size_of(T))
    return
}

make_stack :: proc($T: typeid, cap: int, allocator : mem.Allocator) -> (ret:Stack(T)) {
    ret.allocator = allocator
    ensure_cap(&ret, cap)
    return
}

delete_stack :: proc(using stack: ^Stack($T)) {
    c := context
    if allocator.procedure != nil {
        c.allocator = allocator
    }
    context = c
    delete(buf)
    count = 0
    buf = nil
}

get_stack :: #force_inline proc(using stack: ^Stack($T), index : int) -> T {
    return buf[index]
}

clear_stack :: #force_inline proc(using stack: ^Stack($T)) {
    count = 0
}

ensure_cap :: proc(using stack: ^Stack($T), newCap: int) {
    if newCap > len(buf) {
        c := context
        if allocator.procedure != nil {
            c.allocator = allocator
        }
        context = c

        oldBuffer := buf
        defer delete(oldBuffer)

        buf = make(type_of(buf), newCap)
        if count > 0 {
            mem.copy(&buf[0], &oldBuffer[0], count * size_of(T))
        }
    }
}

push :: #force_inline proc(using stack: ^Stack($T), value: T) {
    if len(buf) == count {
        newCap := len(buf)*2
        if newCap < 8 { newCap = 8 }
        ensure_cap(stack, newCap)
    }
    buf[count]=value
    count+=1
}

pop :: #force_inline proc(using stack: ^Stack($T)) -> (T, bool) {
    if count == 0 {
        return T{}, false
    }

    count-=1
    return buf[count], true
}

pop_n :: #force_inline proc(using stack: ^Stack($T), toPop: int) -> (popped: int) {
    popped = toPop
    if popped > count { popped = count }
    count -= popped
    return
}

// no resize
//@private
RingBuffer :: struct($T: typeid) {
	data:   []T,
	len:    uint,
	offset: uint,
    allocator : mem.Allocator,
}
init_rb :: proc(q: ^$Q/RingBuffer($T), capacity : int, allocator := context.allocator) {
	q.data = make([]T, capacity, allocator)
    q.len = 0
    q.offset = 0
    q.allocator = allocator
	return
}
get_rb :: #force_inline proc "contextless"(q: ^$Q/RingBuffer($T), #any_int i: int, loc := #caller_location) -> T {
	return get_ptr_rb(q, i, loc)^
}
set_rb :: proc "contextless"(q: ^$Q/RingBuffer($T), #any_int i: int, val: T, loc := #caller_location) {
	runtime.bounds_check_error_loc(loc, i, len(q.data))
	
	idx := (uint(i)+q.offset)%len(q.data)
	q.data[idx] = val
}
get_ptr_rb :: proc "contextless"(q: ^$Q/RingBuffer($T), #any_int i: int, loc := #caller_location) -> ^T {
	runtime.bounds_check_error_loc(loc, i, len(q.data))
	
	idx := (uint(i)+q.offset)%len(q.data)
	return &q.data[idx]
}
push_back_rb :: proc "contextless"(q: ^$Q/RingBuffer($T), elem: T) -> bool {
	idx := (q.offset+uint(q.len))%len(q.data)
	q.data[idx] = elem
	if q.len < len(q.data) do q.len += 1
	return true
}
push_front_rb :: proc "contextless"(q: ^$Q/RingBuffer($T), elem: T) -> bool {
	q.offset = uint(q.offset - 1 + len(q.data)) % len(q.data)
	if q.len < len(q.data) do q.len += 1
	q.data[q.offset] = elem
	return true
}

binary_search_min_ge :: proc(buf: []$T, value: $V, cmp: proc(v: V, t: ^T) -> int) -> int {
    lb := 0
    hb := len(buf)-1
    if hb < lb do return lb
    if cmp(value, &buf[hb]) > 0 do return hb+1
    for lb < hb {
        mid := lb + ((hb-lb)>>1)
        if cmp(value, &buf[mid]) > 0 do lb = mid + 1
        else do hb = mid
    }
    return lb
}
