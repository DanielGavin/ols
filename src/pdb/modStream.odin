//! Module Information Stream, ref: https://llvm.org/docs/PDB/ModiStream.html
package pdb
import "core:log"
import "core:slice"
import "core:intrinsics"

ModStreamHeader :: struct #packed {
    signature : ModStreamSignature, // expected to be .C13
}
// symbolsSubStream : [modi.symByteSize-4]byte
// c11LineInfoSubStream : [modi.c11ByteSize]byte
// c13LineInfoSubStream : [modi.c13ByteSize]byte
// globalRefsSize : u32le
// globalRefs: [modi.globalRefsSize]byte

ModStreamSignature :: enum u32le {C7 = 1, C11 = 2, C13 = 4,}

parse_mod_stream :: proc(streamDir: ^StreamDirectory, modi: ^SlimDbiMod) -> (ret: SlimModData) {
    modSr := get_stream_reader(streamDir, modi.moduleSymStream)
    readv(&modSr, ModStreamHeader)
    ret.modStream = modSr.data[modSr.offset:]

    { // symbol substream
        symSubStreamSize := modi.symByteSize - 4
        symSubStreamEnd := modSr.offset + uint(symSubStreamSize)
        defer modSr.offset = symSubStreamEnd
        pStack := make_stack(SlimCvsProc, cast(int)symSubStreamSize / ((size_of(CvsProc32)+size_of(CvsRecordKind))*4), context.temp_allocator); defer delete_stack(&pStack)
        iStack := make_stack(SlimCvsInlineSite, cast(int)symSubStreamSize / ((size_of(CvsInlineSite)+size_of(CvsRecordKind))*4), context.temp_allocator); defer delete_stack(&iStack)
        for modSr.offset < symSubStreamEnd {
            pSelf := CvsOffset(modSr.offset)
            cvsHeader  := readv(&modSr, CvsRecordHeader)
            blockEnd := modSr.offset + uint(cvsHeader.length) - size_of(CvsRecordKind)
            defer modSr.offset = blockEnd
            #partial switch cvsHeader.kind {
            case .S_LPROC32:fallthrough
            case .S_LPROC32_ID:fallthrough
            case .S_LPROC32_DPC:fallthrough
            case .S_LPROC32_DPC_ID:fallthrough
            case .S_GPROC32:fallthrough
            case .S_GPROC32_ID:
                push(&pStack, SlimCvsProc{readv(&modSr, CvsProc32), pSelf})
            case .S_INLINESITE:
                push(&iStack, SlimCvsInlineSite{readv(&modSr, blockEnd, CvsInlineSite), pSelf})
            }
        }
        if pStack.count > 0 {
            ret.procs = make_slice_clone_from_stack(&pStack)
        }
        if iStack.count > 0 {
            ret.inlineSites = make_slice_clone_from_stack(&iStack)
            // sort inline sites by pParent, pEnd
            // this allows us to do binary search on pParent to quickly narrow the range of sites needed for checking
            slice.sort_by(ret.inlineSites, proc(a, b: SlimCvsInlineSite)->bool {
                if a.pParent < b.pParent do return true
                else if a.pParent > b.pParent do return false
                else if a.pEnd < b.pEnd do return true
                else do return false
            })
        }
    }

    {
        // skip c11 lines
        modSr.offset += uint(modi.c11ByteSize)
        c13StreamStart  := modSr.offset
        c13StreamEnd    := modSr.offset + uint(modi.c13ByteSize)
        fileChecksumOffset : Maybe(uint)
        lineBlockCount := 0
        inlineSrcCount := 0
        // first pass
        for modSr.offset < c13StreamEnd {
            ssh := readv(&modSr, CvDbgSubsectionHeader)
            endOffset := modSr.offset + uint(ssh.length)
            //log.debugf("[%v:%v] %v", modSr.offset, endOffset, ssh)
            defer modSr.offset = endOffset
            #partial switch ssh.subsectionType {
            case .FileChecksums: fileChecksumOffset = modSr.offset
            case .Lines: lineBlockCount+=1
            case .InlineeLines:
                islHdr := readv(&modSr, CvDbgssInlineeLinesHeader)
                islSize := uint(size_of(CvDbgInlineeSrcLine))
                if islHdr.signature == .ex {
                    islSize = uint(size_of(CvDbgInlineeSrcLineEx))
                }
                inlineSrcCount += int((endOffset - modSr.offset) / islSize)
            }
        }
        ret.blocks = make([]SlimModLineBlock, lineBlockCount)
        ret.inlineSrcs = make([]SlimModInlineSrc, inlineSrcCount)
        // second pass
        modSr.offset = c13StreamStart
        lineBlockCount = 0
        inlineSrcCount = 0
        for modSr.offset < c13StreamEnd {
            ssh := readv(&modSr, CvDbgSubsectionHeader)
            endOffset := modSr.offset + uint(ssh.length)
            //log.debugf("[%v:%v] %v", modSr.offset, endOffset, ssh)
            defer modSr.offset = endOffset
            #partial switch ssh.subsectionType {
            case .Lines: 
                cBlock := &ret.blocks[lineBlockCount]
                lineBlockCount+=1
                ssLines := readv(&modSr, CvDbgssLinesHeader)
                lineBlock := readv(&modSr, CvDbgLinesFileBlockHeader)
                cBlock^ = SlimModLineBlock{
                    _secOffset = PESectionOffset{offset = ssLines.offset, secIdx = ssLines.seg,},
                    nameOffset = lineBlock.offFile, // unresolved for now
                    lines = make([]SlimModLinePos, lineBlock.nLines),
                }
                for li in 0..<lineBlock.nLines {
                    line := readv(&modSr, CvDbgLinePacked)
                    lns, lne, _ := unpack_lineFlag(line.flags)
                    cBlock.lines[li].offset = line.offset
                    cBlock.lines[li].lineStart = cast(u32le)lns
                }
                if ssLines.flags != .hasColumns && endOffset - modSr.offset == size_of(CvDbgColumn)  * uint(lineBlock.nLines) {
                    log.debug("Flag indicates no column info, but infered from block length we assume column info anyway")
                    ssLines.flags = .hasColumns
                }
                if ssLines.flags == .hasColumns {
                    for li in 0..<lineBlock.nLines {
                        column := readv(&modSr, CvDbgColumn)
                        cBlock.lines[li].colStart = u32le(column.start)
                    }
                }
            case .InlineeLines:
                islHdr := readv(&modSr, CvDbgssInlineeLinesHeader)
                islSize := uint(size_of(CvDbgInlineeSrcLine))
                if islHdr.signature == .ex {
                    islSize = uint(size_of(CvDbgInlineeSrcLineEx))
                }
                for modSr.offset < endOffset {
                    itemEndOffset := modSr.offset + islSize
                    isl := readv(&modSr, CvDbgInlineeSrcLine)
                    //log.debugf("%v", isl)
                    ret.inlineSrcs[inlineSrcCount] = SlimModInlineSrc{isl.inlinee, isl. fileId, isl.srcLineNum, }
                    inlineSrcCount+=1
                }
            }
        }
        // resolve fileIds into nameOffsets
        if fco, ok := fileChecksumOffset.?; ok {
            for i in 0..<len(ret.blocks) {
                modSr.offset = fco + uint(ret.blocks[i].nameOffset)
                checksumHdr := readv(&modSr, CvDbgFileChecksumHeader)
                ret.blocks[i].nameOffset = NamesStream_StartOffset + checksumHdr.nameOffset
                //log.debug(ret.blocks[i].nameOffset)
            }
            for i in 0..<len(ret.inlineSrcs) {
                modSr.offset = fco + uint(ret.inlineSrcs[i].nameOffset)
                checksumHdr := readv(&modSr, CvDbgFileChecksumHeader)
                ret.inlineSrcs[i].nameOffset = NamesStream_StartOffset + checksumHdr.nameOffset
            }
        } else {
            for i in 0..<len(ret.blocks) {
                ret.blocks[i].nameOffset = 0
            }
            for i in 0..<len(ret.inlineSrcs) {
                ret.inlineSrcs[i].nameOffset = 0
            }
        }
        // finally, sort inlineSrcs by inlinee
        slice.sort_by(ret.inlineSrcs, proc(a, b: SlimModInlineSrc)->bool {
            return a.inlinee < b.inlinee
        })
    }

    return
}

SlimCvsProc :: struct {
    using _p : CvsProc32,
    pSelf    : CvsOffset,
}
SlimCvsInlineSite :: struct {
    using _p : CvsInlineSite,
    pSelf    : CvsOffset,
}

SlimModData :: struct {
    modStream   : []byte, // module stream without the stream header, can be directly indexed by Cvs section pointers to read certain stuff
    procs       : []SlimCvsProc,
    blocks      : []SlimModLineBlock,
    inlineSites : []SlimCvsInlineSite,
    inlineSrcs  : []SlimModInlineSrc,
}
SlimModLineBlock :: struct {
    using _secOffset : PESectionOffset,
    nameOffset: u32le, // into the namesStream, with NamesStream_StartOffset already applied.
    lines     : []SlimModLinePos,
}
SlimModLinePos :: struct {lineStart, colStart, offset : u32le,}

SlimModInlineSrc :: struct {
    inlinee    : CvItemId, // TODO: sort by this for quick look up
    nameOffset : u32le, // into the namesStreams
    srcLineNum : u32le,
}

locate_pc :: proc(using data: ^SlimModData, func: PESectionOffset,  pcFromFunc: u32le) -> (csvProc:^SlimCvsProc, lineBlock: ^SlimModLineBlock, line: ^SlimModLinePos){
    for i in 0..<len(procs) {
        //log.debugf("%d/%d:", i, )
        p := &procs[i]
        if p.secIdx == func.secIdx && p.offset == func.offset {
            csvProc = p
            break
        }
    }
    for lbi in 0..<len(blocks) {
        lb := &blocks[lbi]
        if lb.secIdx != func.secIdx || lb.offset != func.offset {
            continue
        }
        lineBlock = lb
        line = &lb.lines[0]
        // ?bisearch?
        for i in 1..<len(lb.lines) {
            cl := &lb.lines[i]
            if cl.offset > pcFromFunc do break
            line = cl
        }
        return
    }
    return
}

locate_inline_site:: proc(using data: ^SlimModData, pParent: CvsOffset, pcFromFunc: u32le) -> (site: ^SlimCvsInlineSite, src: ^SlimModInlineSrc){
    // bisearch on a sorted acceleration structure
    iStart := binary_search_min_ge(inlineSites, pParent, proc(v: CvsOffset, t: ^SlimCvsInlineSite) -> int {
        //log.debugf("Comparing %v with %v", v, t.pParent)
        if v < t.pParent do return -1
        else if v > t.pParent do return 1
        else do return 0
    })
    for i in iStart..<len(inlineSites) {
        if inlineSites[i].pParent != pParent do break
        found := false
        for iline in inlineSites[i].lines {
            if iline.end > pcFromFunc && iline.offset <= pcFromFunc {
                site = &inlineSites[i]
                found = true
                break
            }
        }
        if found do break
    }
    if site == nil do return

    iSite := binary_search_min_ge(inlineSrcs, site.inlinee, proc(v: CvItemId, t: ^SlimModInlineSrc) -> int {
        if v < t.inlinee do return -1
        else if v > t.inlinee do return 1
        else do return 0
    })
    if iSite < len(inlineSrcs) && inlineSrcs[iSite].inlinee == site.inlinee {
        src = &inlineSrcs[iSite]
    }
    return
}

// the C13 CodeView line information format
// reference: https://github.com/willglynn/pdb/blob/master/src/modi/c13.rs
// a variable-size array of SubsectionHeader/Subsection contents
CvDbgSubsectionHeader :: struct #packed {
    subsectionType  : CvDbgSubsectionType,
    length          : u32le,
}
CvDbgSubsectionType :: enum u32 { // DEBUG_S_SUBSECTION_TYPE
    // Native
    Symbols = 0xf1, 
    Lines, 
    StringTable, 
    FileChecksums, 
    FrameData, 
    InlineeLines, 
    CrossScopeImports, 
    CrossScopeExports,
    // .NET
    IlLines, // seems that this can be parsed by SsLinesHeader as well, need further investigation
    FuncMdtokenMap,
    TypeMdtokenMap,
    MergedAssemblyInput,
    CoffSymbolRVA,

    ShouldIgnore = 0x8000_0000, // if set, the subsection content should be ignored
}

// lines subsection starts with this header, then follows the CvDbgLinesFileBlockHeader
CvDbgssLinesHeader :: struct #packed {
    offset  : u32le, // section offset
    seg     : u16le, // seg index in the PDB's section header list, incremented by 1
    flags   : CvDbgssLinesFlags,
    codeSize: u32le,
}
CvDbgssLinesFlags :: enum u16le { none, hasColumns= 0x0001, }

// follows by []CvDbgLinePacked and []CvDbgColumn, if hasColumns
CvDbgLinesFileBlockHeader :: struct #packed {
    offFile : u32le, // offset of the file checksum in the file checksums debug subsection (after reading header)
    nLines  : u32le, // number of lines. if hasColumns, then same number of column entries with follow the line entries buffer
    size    : u32le, // total block size
}

CvDbgLinePacked :: struct #packed {
    offset : u32le, // ?to start of code bytes for line number
    flags  : CvDbgLinePackedFlags,
}
//1       +31|(7)                   +24|(24)        +0
//isStatement, deltaToLineEnd(optional), lineNumStart,
CvDbgLinePackedFlags :: distinct u32le
unpack_lineFlag :: proc(this: CvDbgLinePackedFlags) -> (lineNumStart:u32, lineNumEnd: u32, isStatement: bool) {
    lineNumStart = u32(this & 0xff_ffff)
    dLineEnd := (u32(this) & (0x7f00_0000)) >> 24 // this has been a truncation instead of delta
    lineNumEnd = (lineNumStart & 0x7f) | dLineEnd
    if lineNumEnd < lineNumStart do lineNumEnd += 1 << 7
    isStatement = (this & 0x8000_0000) != 0
    return
}

CvDbgColumn :: struct #packed {
    // byte offsets in a src line
    start : u16le,
    end   : u16le,
}

// InlineeLines subsection, starts with this header, follows with []CvDbgInlineeSrcLine(Ex) depending on the flag
CvDbgssInlineeLinesHeader :: struct #packed {
    signature : CvDbgssInlineeLinesSignature,
}
CvDbgssInlineeLinesSignature :: enum u32le { none = 0x0, ex = 0x1, }

CvDbgInlineeSrcLine :: struct #packed {
    inlinee     : CvItemId, // inlinee function id
    fileId      : u32le, // offset into file table DEBUG_S_FILECHKSMS
    srcLineNum  : u32le, // definition start line number
}
CvDbgInlineeSrcLineEx :: struct {// TODO: read this
    using _base : CvDbgInlineeSrcLine,
    // extraFileCount: u32le,
    extraFileIds: []u32le,
}

// File checksum subsection: []CvDbgFileChecksumHeader(variable length depending on checksumSize and 4byte alignment)
CvDbgFileChecksumHeader :: struct #packed {
    nameOffset  : u32le, // name ref into the global name table(after reading header)
    checksumSize: u8,
    checksumKind: CvDbgFileChecksumKind,
    // then follows the checksum value buffer of len checksumSize
    // then align to 4byte boundary to the next header
}
CvDbgFileChecksumKind :: enum u8 {none, md5, sha1, sha256, }

// TODO: StringTable, FrameData, CrossScopeImports, CrossScopeExports etc

