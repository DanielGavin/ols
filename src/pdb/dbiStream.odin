//! DBI Debug Info Stream reference: https://llvm.org/docs/PDB/DbiStream.html
package pdb
import "core:log"
import "core:intrinsics"

DbiStream_Index :MsfStreamIdx: 3

DbiStreamHeader :: struct #packed {
    versionSignature    : i32le,
    versionHeader       : DbiStreamVersion,
    age                 : u32le,
    globalStreamIndex   : MsfStreamIdx,
    buildNumber         : DbiBuildNumber,
    publicStreamIndex   : MsfStreamIdx,
    pdbDllVersion       : u16le,
    symRecordStream     : u16le,
    pdbDllRbld          : u16le,
    modInfoSize         : i32le,
    secContributionSize : i32le,
    secMapSize          : i32le,
    srcInfoSize         : i32le,
    typeServerMapSize   : i32le,
    mfcTypeServerIndex  : u32le,
    optDbgHeaderSize    : i32le,
    ecSubstreamSize     : i32le,
    flags               : DbiFlags,
    machine             : u16le, // Image File Machine Constants from https://docs.microsoft.com/en-us/windows/win32/sysinfo/image-file-machine-constants
    padding             : u32le,
}
DbiStreamVersion :: enum u32le {
    VC41 = 930803,
    V50 = 19960307,
    V60 = 19970606,
    V70 = 19990903,
    V110 = 20091201,
}
//-|-------|--------|
//+15      +8       +0
//isNew majorVer minorVer
DbiBuildNumber :: distinct u16le
@private
_is_new_version_format :: #force_inline proc (b: DbiBuildNumber) -> bool {
    return (b & (1<<15)) != 0
}

DbiFlags :: enum u16le {
    None = 0x0,
    WasIncrenetallyLinked = 1 << 0,
    ArePrivateSymbolsStripped = 1 << 1,
    HasConflictingTypes = 1 << 2,
}

//==== Module Info Substream, array of DbiModInfos.
DbiModInfo :: struct {
    // using _npm : MsfNotPackedMarker,
    using _base : struct #packed {
        unused1             : u32le,
        sectionContribution : DbiSectionContribution,
        flags               : DbiModInfo_Flags,
        moduleSymStream     : MsfStreamIdx, // index of the stream..
        symByteSize         : u32le,
        c11ByteSize         : u32le,
        c13ByteSize         : u32le,
        sourceFileCount     : u16le,
        padding             : u16le,
        unused2             : u32le,
        sourceFileNameIndex : u32le,
        pdbFilePathNameIndex: u32le,
    },
    moduleName              : string,
    objFileName             : string,
}
DbiModInfo_Flags :: enum u16le {
    None = 0,
    Dirty = 1 << 0,
    EC = 1 << 1, // edit and continue
    // TODO: TypeServerIndex stuff in high8
}
read_dbiModInfo :: proc(this: ^BlocksReader, $T: typeid) -> (ret: T) where intrinsics.type_is_subtype_of(T, DbiModInfo) {
    ret._base = readv(this, type_of(ret._base))
    ret.moduleName = read_length_prefixed_name(this)
    ret.objFileName = read_length_prefixed_name(this)
    // align to 4-byte boundary
    this.offset = (this.offset + 3) & ~uint(3)
    return ret
}

// section contribution sub stream seems to be nicely sorted by section index and offset
// based on function rva, we can bisearch this array to locate the module.
DbiSecContrVersion :: enum u32le {
    Ver60 = 0xeffe0000 + 19970605,
    V2 = 0xeffe0000 + 20140516,
}
DbiSectionContribution :: struct #packed {
    section         : u16le,
    padding1        : u16le,
    offset          : u32le,
    size            : u32le,
    characteristics : u32le,
    moduleIndex     : u16le, // index into the module substream
    padding2        : u16le,
    dataCrc         : u32le,
    relocCrc        : u32le,
}
DbiSectionContribution2 :: struct #packed {
    using sc  : DbiSectionContribution,
    iSectCoff : u32le,
}

DbiSecMapHeader :: struct #packed {
    count   : u16le, // segment descriptors
    logCount: u16le, // logival segment descriptors
}
DbiSecMapEntry :: struct #packed {
    flags           : DbiSecMapEntryFlags,
    ovl             : u16le,
    group           : u16le,
    frame           : u16le,
    sectionName     : u16le,
    className       : u16le,
    offset          : u32le,
    sectionLength   : u32le,
}
DbiSecMapEntryFlags :: enum u16le {
    None = 0,
    Read = 1 << 0,
    Write = 1 << 1,
    Execute = 1 << 2,
    AddressIs32Bit = 1 << 3,
    IsSelector = 1 << 8,
    IsAbsoluteAddress = 1 << 9,
    IsGroup = 1 << 10,
}

DbiFileInfos :: struct {
    using _npm : MsfNotPackedMarker,
    // numModules :: u16le
    // numSourceFiles :: u16le
    // modIndices      : []u16le, // len==numModules
    modFileCounts   : []u16le, // len==numModules
    srcFileNames    : []string, // fileNameOffsets : []u32le,
    // namesBuffer     : []string,
}
read_dbiFileInfos :: proc(this: ^BlocksReader, $T: typeid) -> (ret: T) where intrinsics.type_is_subtype_of(T, DbiFileInfos) {
    moduleCount := readv(this, u16le)
    readv(this, u16le) // ignored invalid src count
    //log.debugf("Module count: %v", moduleCount)
    this.offset += size_of(u16le) * uint(moduleCount) // skip unused mod indices
    ret.modFileCounts = make([]u16le, cast(int)moduleCount)
    srcFileSum :uint=0
    for i in 0..<len(ret.modFileCounts) {
        ret.modFileCounts[i] = readv(this, u16le)
        srcFileSum += uint(ret.modFileCounts[i])
    }
    //log.debugf("Src File count: %v", srcFileSum)
    nameMap := make(map[u32le]string, srcFileSum, context.temp_allocator)
    defer delete(nameMap)
    ret.srcFileNames = make([]string, srcFileSum)
    nameBufOffset := this.offset + size_of(u32le) * srcFileSum
    for i in 0..<srcFileSum {
        baseOffset := this.offset
        defer this.offset = baseOffset + size_of(u32le)
        nameOffset := readv(this, u32le)
        existingName, nameExist := nameMap[nameOffset]
        if nameExist {
            ret.srcFileNames[i] = existingName
        } else {
            this.offset = nameBufOffset + uint(nameOffset)
            ret.srcFileNames[i] = read_length_prefixed_name(this)
            nameMap[nameOffset] = ret.srcFileNames[i]
        }
        
    }
    return
}

// TODO: Type Server Map Substream, EC Substream

// Optional Debug Header Streams
DbiOptDbgHeaders :: struct #packed {
    framePointerOmission: MsfStreamIdx,
    exception           : MsfStreamIdx,
    fixup               : MsfStreamIdx,
    omapToSrc           : MsfStreamIdx, // []PEOMapRecord
    omapFromSrc         : MsfStreamIdx, // []PEOMapRecord
    sectionHeader       : MsfStreamIdx, // []PESectionHeader in pdb (or original if identical)
    tokenToRID          : MsfStreamIdx,
    xdata               : MsfStreamIdx,
    pdata               : MsfStreamIdx,
    newFPO              : MsfStreamIdx,
    oSectionHeader      : MsfStreamIdx, // []PESectionHeader in original file (if not identical)
}

// data that's essential for sourcecode lookup
SlimDbiData :: struct {
    modules       : []SlimDbiMod,
    contributions : []SlimDbiSecContr, // sorted by section/offset, deduplicated on module
    sections      : []SlimDbiSecInfo,
    // TODO: omap lookup for rva transition
}
@private
_cmp_sc :: #force_inline proc(l, r: SlimDbiSecContr) -> int {
    if l.secIdx < r.secIdx do return -1
    else if l.secIdx > r.secIdx do return 1
    else if l.offset < r.offset do return -1
    else if l.offset > r.offset do return 1
    return 0
}
search_for_section_contribution :: proc(using this: ^SlimDbiData, imgRva : u32le) -> (sci : int) {
    sectionIdx := -1
    offsetInSection :u32le= 0
    for section, i in sections {
        if imgRva >= section.vAddr && imgRva < section.vAddr + section.vSize {
            sectionIdx = i
            //log.debug(section)
            offsetInSection = imgRva - section.vAddr
            break
        }
    }
    if sectionIdx == -1 do return -1
    // bisearch for module
    ti := SlimDbiSecContr{PESectionOffset{offsetInSection, u16le(sectionIdx+1),}, 0}
    lo, hi := 0, (len(contributions)-1)
    if hi < 0 || _cmp_sc(ti, contributions[lo]) < 0 do return -1
    if _cmp_sc(contributions[hi], ti) < 0 do return int(hi)
    // ti in range, do a bisearch
    for lo <= hi {
        mid := lo + ((hi-lo)>>1)
        mv := _cmp_sc(ti, contributions[mid])
        if mv == 0 {
            lo = mid + 1
            break
        }
        else if mv < 0 do hi = mid - 1
        else do lo = mid + 1
    }
    if lo > 0 do lo -= 1
    return int(lo)
}

SlimDbiMod :: struct {
    moduleName        : string,
    objFileName       : string,
    symByteSize       : u32le,
    c11ByteSize       : u32le,
    c13ByteSize       : u32le,
    secContrOffset    : PESectionOffset, // pdb section offset of its first section contribution. this is useful for module address hashing
    moduleSymStream   : MsfStreamIdx,
}
SlimDbiSecContr :: struct {
    using _secOffset : PESectionOffset,
    module           : u16le, // 0-indexed module id into []modules
}
SlimDbiSecInfo :: struct {
    name    : PESectionName,
    vSize   : u32le,
    vAddr   : u32le,
}

parse_dbi_stream :: proc(streamDir: ^StreamDirectory) -> (ret : SlimDbiData) {
    dbiSr := get_stream_reader(streamDir, DbiStream_Index)
    this := &dbiSr
    header := readv(this, DbiStreamHeader)
    if header.versionSignature != -1 {
        log.warnf("unrecognized dbiVersionSignature: %v", header.versionSignature)
    }
    if header.versionHeader != .V70 {
        log.warnf("unrecognized dbiVersionHeader: %v", header.versionHeader)
    }
    if !_is_new_version_format(header.buildNumber) {
        log.warnf("unrecognized old dbiBuildNumber: %v", header.buildNumber)
    }
    { // Module Info substream
        stack := make_stack(SlimDbiMod, int(header.modInfoSize / size_of(DbiModInfo)), context.temp_allocator)
        defer delete_stack(&stack)
        substreamEnd := uint(header.modInfoSize) + this.offset
        defer assert(this.offset == substreamEnd)
        for this.offset < substreamEnd {
            modi := readv(this, DbiModInfo)
            push(&stack, SlimDbiMod{modi.moduleName, modi.objFileName, modi.symByteSize, modi.c11ByteSize, modi.c13ByteSize, PESectionOffset{offset = modi.sectionContribution.offset, secIdx = modi.sectionContribution.section,}, modi.moduleSymStream})
        }
        if stack.count > 0 {
            ret.modules = make_slice_clone_from_stack(&stack)
        }
    }
    { // section contribution substream
        substreamEnd := uint(header.secContributionSize) + this.offset
        defer assert(this.offset == substreamEnd)
        secContrSubstreamVersion := readv(this, DbiSecContrVersion)
        //log.debug(secContrSubstreamVersion)
        secContrEntrySize := size_of(DbiSectionContribution)
        switch secContrSubstreamVersion {
        case .Ver60:
        case .V2: secContrEntrySize = size_of(DbiSectionContribution2)
        case: assert(false, "Invalid DbiSecContrVersion")
        }
        itemCount := (substreamEnd - this.offset) / uint(secContrEntrySize)
        assert(itemCount > 0)
        lastItem : SlimDbiSecContr
        {
            baseOffset := this.offset
            defer this.offset = baseOffset + cast(uint)secContrEntrySize
            secContr := readv(this, DbiSectionContribution)
            lastItem = SlimDbiSecContr{
                PESectionOffset{secContr.offset, secContr.section,}, secContr.moduleIndex,
            }
        }
        stack := make_stack(SlimDbiSecContr, int(itemCount), context.temp_allocator)
        defer delete_stack(&stack)
        for this.offset < substreamEnd {
            baseOffset := this.offset
            defer this.offset = baseOffset + cast(uint)secContrEntrySize
            secContr := readv(this, DbiSectionContribution)
            if secContr.size == 0 do continue
            //log.debug(secContr)
            assert(secContr.section > lastItem.secIdx || secContr.offset > lastItem.offset)
            if secContr.section != lastItem.secIdx || secContr.moduleIndex != lastItem.module {
                // new
                push(&stack, lastItem)
                lastItem = SlimDbiSecContr{
                    {secContr.offset, secContr.section,}, secContr.moduleIndex,
                }
            } else {
                // cumulate
                lastItem.offset = secContr.offset
            }
        }
        push(&stack, lastItem)
        ret.contributions = make_slice_clone_from_stack(&stack)
    }
    // skip irrelevant streams
    this.offset += uint(header.secMapSize)
    this.offset += uint(header.srcInfoSize)
    this.offset += uint(header.typeServerMapSize)
    this.offset += uint(header.ecSubstreamSize)
    optDbgHeaders := readv(this, DbiOptDbgHeaders)
    if stream_idx_valid(optDbgHeaders.sectionHeader) {
        sectionRdr := get_stream_reader(streamDir, optDbgHeaders.sectionHeader)
        sectionLen := sectionRdr.size / size_of(PESectionHeader)
        ret.sections = make([]SlimDbiSecInfo, sectionLen)
        for i in 0..<sectionLen {
            secHdr := readv(&sectionRdr, PESectionHeader)
            ret.sections[i] = SlimDbiSecInfo{secHdr.name, secHdr.vSize, secHdr.vAddr, }
        }
        // TODO: omaps and stuff
        if stream_idx_valid(optDbgHeaders.oSectionHeader) {
            log.warn("oSection presented presented, need RVA remap!")
        }
    }
    return
}
