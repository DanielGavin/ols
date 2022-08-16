//! reference: https://docs.microsoft.com/en-us/windows/win32/debug/pe-format
package pdb
import "core:log"
import "core:fmt"
import "core:slice"
import "core:io"

PE_Signature_OffsetIdxPos :: 0x3c // ?u32le?
PE_Signature :u32le: 0x0000_4550 //PE\0\0

// At the beginning of an object file, or immediately after the signature of an image file
CoffFileHeader :: struct #packed {
    machine     : PEMachineType,
    numSecs     : u16le, // number of sections following the header
    dateStamp   : u32le,
    pSymTable   : u32le, // offset to COFF symbol table 0 if not presented
    numSyms     : u32le,
    optHdrSize  : u16le, // size of optional header following this
    charas      : PECharacteristics, 
}
PEMachineType :: enum u16le { // IMAGE_FILE_MACHINE_xx
    Unknown = 0x0, // assumed to be applicable to any machine type
    AM33 = 0x1d3, // Matsushita AM33
    Amd64 = 0x8664, // x64
    Arm = 0x1c0, // ARM little endian
    Arm64 = 0xaa64, //ARM64 little endian
    ArmNT = 0x1c4, //ARM Thumb-2 little endian
    EBC = 0xebc, //EFI byte code
    I386 = 0x14c, //Intel 386 or later processors and compatible processors
    IA64 = 0x200, //Intel Itanium processor family
    LoongArch32 = 0x6232,
    LoongArch64 = 0x6264,
    M32R = 0x9041, //Mitsubishi M32R little endian
    Mips16 = 0x266,
    MipsFpu = 0x366,
    MipsFpu16 = 0x466,
    PowerPC = 0x1f0, //Power PC little endian
    PowerPCFP = 0x1f1, //Power PC with floating point support
    R4000 = 0x166, //MIPS little endian
    RiscV32 = 0x5032, //RISC-V
    RiscV64 = 0x5064, //RISC-V
    RiscV128 = 0x5128, //RISC-V
    SH3 = 0x1a2, //Hitachi SH3
    SH3DSP = 0x1a3, //Hitachi SH3 DSP
    SH4 = 0x1a6, //Hitachi SH4
    SH5 = 0x1a8, //Hitachi SH5
    Thumb = 0x1c2,
    WCEMipsV2 = 0x169, //MIPS little-endian WCE v2
}
PECharacteristics :: enum u16le {// IMAGE_FILE_xxxx
    None = 0,
    RelocsStripped = 0x0001, //Image only, file does not contain base relocations
    ExeImage = 0x0002, //Image only. This indicates that image is valid and can be run
    _LineNumsStripped = 0x0004, //deprecated COFF stuff, should be zero.
    _LocalSymsStripped = 0x0008, //deprecated COFF stuff, should be zero.
    _AggressiveWorkingSetTrim = 0x0010, //Obsolete, must be zero.
    LargeAddressAware = 0x0020, //Application can handle > 2-GB addresses.
    _Reserved0 = 0x0040, //This flag is reserved for future use.
    _BytesReservedLo = 0x0080, //deprecated and should be zero.
    Machine32bit = 0x0100, //Machine is based on a 32-bit-word architecture.
    DebugStripped = 0x0200, //Debugging information is removed from image.
    RemovableRunFromSwap = 0x0400, //If on removable media, fully load to the swap file.
    NetRunFromSwap = 0x0800, //If on network media, fully load to the swap file.
    System = 0x1000, //image is a system file
    Dll = 0x2000, //image is a dynamic-link library (DLL)
    SystemOnly = 0x4000, //The file should be run only on a uniprocessor machine.
    _BytesReservedHi = 0x8000, //deprecated and should be zero.
}
PEOptHdrMagic :: enum u16le { PE32 = 0x10b, PE32Plus = 0x20b, }
PEOptHdr :: struct #packed {
    standard : PEOptHdr_StandardOld,
    windows  : PEOptHdr_Win,
}
PEOptHdrPlus :: struct #packed {
    standard : PEOptHdr_Standard,
    windows  : PEOptHdr_WinPlus,
}
PEOptHdr_Standard :: struct #packed {
    // magic : PEOptHdrMagic
    majorLinkerVer  : u8,
    minorLinkerVer  : u8,
    codeSize        : u32le, // (sum)size of code(text) section(s)
    initDataSize    : u32le, // (sum)size of initialized data section(s)
    uninitDataSize  : u32le, // (sum)size of BSS data section(s)
    entryPointAddr  : u32le, // address of entry point relative to image base
    codeBaseAddr    : u32le, // address of beginning of code section relative to image base
}
PEOptHdr_StandardOld :: struct #packed {
    using _base     : PEOptHdr_Standard,
    dataBaseAddr    : u32le, // address of beginning of data section relative to image base
}
PEOptHdr_Win :: _PEOptHdr_WinImpl(u32le)
PEOptHdr_WinPlus :: _PEOptHdr_WinImpl(u64le)
_PEOptHdr_WinImpl :: struct($T: typeid) #packed {
    imageBase       : T, // preferred address of image when loaded in memory
    sectionAlignment: u32le, // section alignment when loaded in mem
    fileAlignment   : u32le, // alignment used to align raw section data in image file
    majorOSVer      : u16le,
    minorOSVer      : u16le,
    majorImageVer   : u16le,
    minorImageVer   : u16le,
    majorSubsysVer  : u16le,
    minorSubsysVer  : u16le,
    _win32Ver       : u32le, // reserved, must be 0
    imageSize       : u32le, // size of image when loaded in mem
    headersSize     : u32le, // size of MS-DOS stub, PE and section headers, aligned to fileAlignment
    checksum        : u32le, // image file checksum
    subsystem       : PEWinSubsystem,
    dllCharas       : PEDllCharacteristics,
    stackSizeReserve: T,
    stackSizeCommit : T,
    heapSizeReserve : T,
    heapSizeCommit  : T,
    _loaderFlags    : u32le, // reserved, must be 0
    dataDirCount    : u32le, // count of data-directory entries in the remainder of OptHdr
}
PEWinSubsystem :: enum u16le {
    Unknown = 0, Native = 1, WinGUI = 2, WinCUI = 3, OS2CUI = 5, PosixCUI = 7,
    NativeWin9x = 8, WinCEGUI = 9, EFIApp = 10, EFIServiceDriver = 11, 
    EFIRuntimeDriver = 12, EFIRom = 13, Xbox = 14, WinBootApp = 16,
}
PEDllCharacteristics :: enum u16le {
    HighEntropyVA = 0x0020, // can handle a high entropy 64-bit virtual address space
    DynamicBase = 0x0040,  // can be relocated at runtime
    ForceIntegrity = 0x0080,
    NXCompat = 0x0100,
    NoIsolation = 0x0200,
    NoSEH = 0x0400,
    NoBind = 0x0800,
    AppContainer = 0x1000,
    WDMDriver = 0x2000,
    GuardCF = 0x4000,
    TerminalServerAware = 0x8000,
}

// might not be fully valid: only optHdrWin.dataDirCount available
PEOptHdr_DataDirectories :: struct #packed {
    edata,  // export table
    idata,  // import table
    rsrc,   // resource table
    pdata,  // exception table
    attrCert, // attribute certificate table
    reloc,  // base relocation table
    debug,  // debug data table
    _architecture, // reserved
    globalPtr, // global pointer register. size==0
    tls, // thread local storage table
    loadConfig, // load configuration table
    boundImport, // bound import table
    iat, // import address table
    delayLoadImport, // delay-load import tables
    clrRuntime, // clr runtime headers
    _reserved: PEOptHdr_DataDirectory, 
}
// RVA: address of the table relative to image base address after loaded
PEOptHdr_DataDirectory :: struct #packed { rva, size: u32le, }

// section table directly follows all the headers above, numbers given by coffHdr.numSecs
PESectionHeader :: struct #packed {
    name    : PESectionName, // formatting string using fmt.register_user_formatter, or slash+decimal ascii number as offset into string table
    vSize   : u32le, // size of section when loaded into memory
    vAddr   : u32le, // address of section relative to image base when loaded (for exe)
    rawSize : u32le, // size of raw data on disk
    pRaw    : u32le, // file pointer to the first page of the section within COFF file
    pRelocs : u32le, // file pointer to relocation entries for the section
    pLines  : u32le, // file pointer to COFF line-number entries, 0 if none
    relocNum: u16le, // numbre of relocation entries
    lineNum : u16le, // number of line-number entries
    flags   : PESectionFlags,
}
PESectionName :: struct #raw_union {buf: [8]byte, num: u64le,}
peSectionName_formatter :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
    n := arg.(PESectionName)
    io.write_rune(fi.writer, '"', &fi.n)
    for i in 0..<len(n.buf) {
        if n.buf[i] == 0 do break
        io.write_rune(fi.writer, rune(n.buf[i]), &fi.n)
    }
    io.write_string(fi.writer, "\"(0x", &fi.n)
    io.write_u64(fi.writer, u64(n.num), 16, &fi.n)
    io.write_rune(fi.writer, ')', &fi.n)
    return true
}
PESectionOffset :: struct #packed {offset: u32le, secIdx: u16le,}
PESectionFlags :: enum u32le {
    None = 0,
    NoPad = 0x0000_0008, // obsolete, replaced by Align1
    CntCode = 0x0000_0020,
    CntInitData = 0x0000_0040,
    CntUninitData = 0x0000_0080,
    LnkInfo = 0x0000_0200, // comments or ther info. .drectve section. valid for object files
    LnkRemove = 0x0000_0800, // section will not become part of image. valid for object files
    LnkComdat = 0x0000_1000, // COMDAT data
    GlobalPointerRel = 0x0000_8000, // contains data referenced through global pointer(GP)
    // alignments, valid for object files
    Align1    = 0x0010_0000,
    Align2    = 0x0020_0000,
    Align4    = 0x0030_0000,
    Align8    = 0x0040_0000,
    Align16   = 0x0050_0000,
    Align32   = 0x0060_0000,
    Align64   = 0x0070_0000,
    Align128  = 0x0080_0000,
    Align256  = 0x0090_0000,
    Align512  = 0x00a0_0000,
    Align1024 = 0x00b0_0000,
    Align2048 = 0x00c0_0000,
    Align4096 = 0x00d0_0000,
    Align8192 = 0x00e0_0000,
    LnkNRelocOvfl = 0x0100_0000, // indicates that relocNum overflows 0xffff. If set and relocNum==0xffff, then actual count is stored in the rva field of the first relocation.
    MemDiscardable = 0x0200_0000,
    MemNotCached = 0x0400_0000,
    MemNotPaged = 0x0800_0000,
    MemShared = 0x1000_0000,
    MemExecute = 0x2000_0000,
    MemRead = 0x4000_0000,
    MemWrite = 0x8000_0000,
}

// TODO: COFF Relocations

//.debug secion: Debug Directory
PEDebugDirEntry :: struct #packed {
    flags       : u32le, // reserved, must be 0
    dateStamp   : u32le,
    majorVer    : u16le,
    minorVer    : u16le,
    debugType   : PEDebugType,
    dataSize    : u32le, // excluding the directory itself
    rawDataAddr : u32le, // address of debug data when loaded
    pRawData    : u32le, // file pointer to raw data on disk
}
PEDebugType :: enum u32le {
    Unknown = 0,
    COFF = 1, // The COFF debug information
    CodeView = 2, // The Visual C++ debug information.
    FPO = 3, // The frame pointer omission (FPO) information. This information tells the debugger how to interpret nonstandard stack frames, which use the EBP register for a purpose other than as a frame pointer.
    Misc = 4, // The location of DBG file.
    Exception = 5, // A copy of .pdata section.
    Fixup = 6, // Reserved.
    OmapToSrc = 7, // RVA mapping to src
    OmapFromSrc = 8, // RVA mapping from src
    BORLAND = 9, // Reserved for Borland.
    Reserved10 = 10, // Reserved.
    CLSID = 11, // Reserved.
    Repro = 16, // PE determinism or reproducibility.
    ExtendedDllCharacteristics = 20, // Extended DLL characteristics bits.
}

// record applies to the half-open intervals in the array
PEOMapRecord :: struct #packed { sourceAddr, targetAddr: u32le, }

PECodeViewInfoPdb70 :: struct {
    using _base : PECodeViewInfoPdb70Base,
    name        : string,
}
PECodeViewInfoPdb70Base :: struct #packed {
    cvSignature : u32le, // should be PECodeView_Signature_RSDS
    guid        : u128le,
    age         : u32le,
}
PECodeView_Signature_RSDS :u32le: 0x5344_5352

parse_pe_data_dirs :: proc(r: io.Stream) -> (ret : PEOptHdr_DataDirectories, err: io.Error) {
    r->impl_seek(PE_Signature_OffsetIdxPos, .Start) or_return
    peSigOffset := read_packed_from_stream(r, u32le) or_return
    r->impl_seek(i64(peSigOffset), .Start) or_return
    PEPlusDataDirEnd :: size_of(u32le) + size_of(CoffFileHeader) + size_of(PEOptHdrMagic) + size_of(PEOptHdrPlus) + size_of(PEOptHdr_DataDirectories)
    
    buf :[PEPlusDataDirEnd]byte
    r->impl_read(buf[:]) or_return
    br := make_dummy_reader(buf[:])
    _, _, dataDirs := read_pe_headers(&br)
    return dataDirs, nil
}

seek_to_pe_headers :: proc(this: ^BlocksReader) {
    this.offset = PE_Signature_OffsetIdxPos
    peSigOffset := readv(this, u32le)
    this.offset = uint(peSigOffset)
}

read_pe_headers :: proc(this: ^BlocksReader) -> (coffHdr : CoffFileHeader, optHdr: union{PEOptHdr, PEOptHdrPlus}, dataDirs : PEOptHdr_DataDirectories) {
    // start from PE_Signature
    signature := readv(this, u32le)
    if signature != PE_Signature {
        log.warnf("Invalid signature 0x%x", signature)
        return
    }
    coffHdr = readv(this, CoffFileHeader)
    optHdrMagic := readv(this, PEOptHdrMagic)
    switch optHdrMagic {
    case .PE32: optHdr = readv(this, PEOptHdr)
    case .PE32Plus: optHdr = readv(this, PEOptHdrPlus)
    case: assert(false, "Invalid PEOptional Header Magic number")
    }
    { // dataDir, limited read
        dataDirCount : u32le
        switch h in optHdr {
        case PEOptHdr: dataDirCount = h.windows.dataDirCount
        case PEOptHdrPlus: dataDirCount = h.windows.dataDirCount
        case: assert(false)
        }
        assert(dataDirCount * size_of(PEOptHdr_DataDirectory) <= size_of(PEOptHdr_DataDirectories), "dataDir overflow")
        ddSlice := slice.from_ptr(cast(^PEOptHdr_DataDirectory)&dataDirs, int(dataDirCount))
        for i in 0..<len(ddSlice) {
            ddSlice[i] = readv(this, PEOptHdr_DataDirectory)
        }
    }
    return
}

