package pdb
import "core:os"
import "core:slice"
import "core:strings"
import "core:intrinsics"
import "core:runtime"
import "core:io"
import "core:sync"
import "core:path/filepath"
import windows "core:sys/windows"
foreign import ntdll_lib "system:ntdll.lib"
foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention="std")
foreign ntdll_lib {
    RtlCaptureStackBackTrace  :: proc(FramesToSkip : DWORD, FramesToCapture: DWORD, BackTrace: ^rawptr, BackTraceHash: ^DWORD) -> WORD ---
    RtlCaptureContext :: proc(ContextRecord : ^CONTEXT) ---
    RtlLookupFunctionEntry :: proc(ControlPc : DWORD64, ImageBase: ^DWORD64, HistoryTable: ^UNWIND_HISTORY_TABLE) -> ^RUNTIME_FUNCTION ---
    RtlVirtualUnwind :: proc(
        HandlerType : DWORD,
        ImageBase: DWORD64,
        ControlPC: DWORD64,
        FunctionEntry: ^RUNTIME_FUNCTION,
        ContextRecord: ^CONTEXT,
        HandlerData: ^rawptr, 
        EstablisherFrame: ^DWORD64, 
        ContextPointers: ^KNONVOLATILE_CONTEXT_POINTERS,
    ) -> EXCEPTION_ROUTINE ---
}

@(default_calling_convention="stdcall")
foreign kernel32 {
    SetUnhandledExceptionFilter :: proc(lpTopLevelExceptionFilter: PTOP_LEVEL_EXCEPTION_FILTER) -> PTOP_LEVEL_EXCEPTION_FILTER ---
}

RUNTIME_FUNCTION :: struct {
    BeginAddress : DWORD,
    EndAddress   : DWORD,
    using _dummyU: struct #raw_union {
        UnwindData : DWORD,
        UnwindInfoAddress : DWORD,
    },
}
BYTE    :: windows.BYTE
WORD    :: windows.WORD
DWORD   :: windows.DWORD
PTOP_LEVEL_EXCEPTION_FILTER :: windows.PVECTORED_EXCEPTION_HANDLER
DWORD64 :: u64
NEON128 :: struct {Low: u64, High: i64,}
ARM64_MAX_BREAKPOINTS :: 8
ARM64_MAX_WATCHPOINTS :: 1
M128A :: struct #align 16 #raw_union {
    using _base : struct { Low: u64, High: i64, },
    _v128 : i128,
}
EXCEPTION_ROUTINE :: #type proc "stdcall" (ExceptionRecord: ^windows.EXCEPTION_RECORD, EstablisherFrame: rawptr, ContextRecord: ^CONTEXT, DispatcherContext: rawptr) -> windows.EXCEPTION_DISPOSITION
UNWIND_HISTORY_TABLE_SIZE :: 12
CONTEXT :: _AMD64_CONTEXT
KNONVOLATILE_CONTEXT_POINTERS :: _AMD64_KNONVOLATILE_CONTEXT_POINTERS
UNWIND_HISTORY_TABLE :: _AMD64_UNWIND_HISTORY_TABLE
UNWIND_HISTORY_TABLE_ENTRY :: _AMD64_UNWIND_HISTORY_TABLE_ENTRY

_AMD64_CONTEXT :: struct #align 16 {
    // register parameter home addresses
    P1Home,P2Home,P3Home,P4Home,P5Home,P6Home: DWORD64,
    // control flags
    ContextFlags,MxCsr: DWORD,
    // segment registers and processor flags
    SegCs,SegDs,SegEs,SegFs,SegGs,SegSs: WORD, EFlags: DWORD,
    // debug registers
    Dr0,Dr1,Dr2,Dr3,Dr6,Dr7: DWORD64,
    // integer registers
    Rax,Rcx,Rdx,Rbx,Rsp,Rbp,Rsi,Rdi,R8,R9,R10,R11,R12,R13,R14,R15: DWORD64,
    // program counter
    Rip: DWORD64,
    // Floating point state
    using _dummyU : struct #raw_union {
        FltSave: XMM_SAVE_AREA32,
        using _dummyS : struct {
            Header: [2]M128A,
            Legacy: [8]M128A,
            Xmm0,Xmm1,Xmm2,Xmm3,Xmm4,Xmm5,Xmm6,Xmm7,Xmm8,Xmm9,Xmm10,Xmm11,Xmm12,Xmm13,Xmm14,Xmm15: M128A,
        },
    },
    // Vector registers
    VectorRegister: [26]M128A, VectorControl: DWORD64,
    // special debug control registers
    DebugControl,LastBranchToRip,LastBranchFromRip,LastExceptionToRip,LastExceptionFromRip: DWORD64,
}
XMM_SAVE_AREA32 :: struct #align 16 { // _XSAVE_FORMAT
    ControlWord : WORD,
    StatusWord : WORD,
    TagWord : BYTE,
    Reserved1 : BYTE,
    ErrorOpcode : WORD,
    ErrorOffset : DWORD,
    ErrorSelector : WORD,
    Reserved2 : WORD,
    DataOffset : DWORD,
    DataSelector : WORD,
    Reserved3 : WORD,
    MxCsr : DWORD,
    MxCsr_Mask : DWORD,
    FloatRegisters : [8]M128A,

    XmmRegisters : [16]M128A,
    Reserved4 : [96]BYTE,
}
_AMD64_KNONVOLATILE_CONTEXT_POINTERS :: struct {
    using _dummyU        : struct #raw_union {
        FloatingContext  : [16]^M128A,
        using _dummyS    : struct {
            Xmm0, Xmm1, Xmm2, Xmm3,
            Xmm4, Xmm5, Xmm6, Xmm7,
            Xmm8, Xmm9, Xmm10,Xmm11,
            Xmm12,Xmm13,Xmm14,Xmm15: ^M128A,
        },
    },
    using _dummyU2       : struct #raw_union {
        IntegerContext   : [16]^u64,
        using _dummyS2   : struct {
            Rax, Rcx, Rdx, Rbx,
            Rsp, Rbp, Rsi, Rdi,
            R8,  R9,  R10, R11,
            R12, R13, R14, R15 : ^u64,
        },
    },
}
_AMD64_UNWIND_HISTORY_TABLE :: struct {
    Count       : DWORD,
    LocalHint   : BYTE,
    GlobalHint  : BYTE,
    Search      : BYTE,
    Once        : BYTE,
    LowAddress  : DWORD64,
    HighAddress : DWORD64,
    Entry       : [UNWIND_HISTORY_TABLE_SIZE]_AMD64_UNWIND_HISTORY_TABLE_ENTRY,
}
_AMD64_UNWIND_HISTORY_TABLE_ENTRY :: struct {
    ImageBase     : DWORD64,
    FunctionEntry : ^RUNTIME_FUNCTION,
}

// TODO: arm bindings
// _ARM64_NT_CONTEXT :: struct {
//     ContextFlags      : DWORD,
//     Cpsr              : DWORD,
//     using _dummyU     : struct #raw_union {
//         X             : [31]DWORD64,
//         using _dummyS : struct {
//             X0, X1, X2, X3, X4, X5, X6, X7,   
//             X8, X9, X10,X11,X12,X13,X14,X15,  
//             X16,X17,X18,X19,X20,X21,X22,X23,  
//             X24,X25,X26,X27,X28,Fp, Lr : DWORD64,
//         },
//     },
//     Sp                : DWORD64,
//     Pc                : DWORD64,
//     V                 : [32]NEON128,
//     Fpcr              : DWORD,
//     Fpsr              : DWORD,
//     Bcr               : [ARM64_MAX_BREAKPOINTS]DWORD,
//     Bvr               : [ARM64_MAX_BREAKPOINTS]DWORD64,
//     Wcr               : [ARM64_MAX_WATCHPOINTS]DWORD,
//     Wvr               : [ARM64_MAX_WATCHPOINTS]DWORD64,
// }

StackFrame :: struct {
    progCounter : uintptr, // instruction pointer
    imgBaseAddr : uintptr,
    funcBegin   : u32,  // rva marking the beginning of the function
    funcEnd     : u32,  // rva marking the end of the function
}

capture_stack_trace :: #force_no_inline proc "contextless" (traceBuf: []StackFrame) -> (count : uint) {
    fImgBase : DWORD64
    ctx : CONTEXT
    RtlCaptureContext(&ctx)
    handlerData : rawptr
    establisherFrame : DWORD64
    // skip current frame
    rtFunc := RtlLookupFunctionEntry(ctx.Rip, &fImgBase, nil)
    RtlVirtualUnwind(0, fImgBase, ctx.Rip, rtFunc, &ctx, &handlerData, &establisherFrame, nil)
    
    for count = 0; count < len(traceBuf); count+=1 {
        rtFunc = RtlLookupFunctionEntry(ctx.Rip, &fImgBase, nil)
        if rtFunc == nil do break
        pst := &traceBuf[count]
        pst.progCounter = cast(uintptr)ctx.Rip
        pst.imgBaseAddr = cast(uintptr)fImgBase
        pst.funcBegin   = rtFunc.BeginAddress
        pst.funcEnd     = rtFunc.EndAddress
        RtlVirtualUnwind(0, fImgBase, ctx.Rip, rtFunc, &ctx, &handlerData, &establisherFrame, nil)
    }
    return
}

capture_stack_trace_from_context :: proc "contextless" (ctx: ^CONTEXT, traceBuf: []StackFrame) -> (count : uint) {
    fImgBase : DWORD64
    handlerData : rawptr
    establisherFrame : DWORD64
    for count = 0; count < len(traceBuf); count+=1 {
        rtFunc := RtlLookupFunctionEntry(ctx.Rip, &fImgBase, nil)
        if rtFunc == nil do break
        pst := &traceBuf[count]
        pst.progCounter = cast(uintptr)ctx.Rip
        pst.imgBaseAddr = cast(uintptr)fImgBase
        pst.funcBegin   = rtFunc.BeginAddress
        pst.funcEnd     = rtFunc.EndAddress
        RtlVirtualUnwind(0, fImgBase, ctx.Rip, rtFunc, ctx, &handlerData, &establisherFrame, nil)
    }
    return
}

_PEModuleInfo :: struct {
    filePath     : string,
    pdbPath      : string,
    pdbHandle    : os.Handle,
    streamDir    : StreamDirectory,
    namesStream  : BlocksReader,
    dbiData      : SlimDbiData,
    ipiStream    : BlocksReader,
    ipiOffsetBuf : TpiIndexOffsetBuffer,
}

parse_stack_trace :: proc(stackTrace: []StackFrame, sameProcess: bool, srcCodeLocs: ^RingBuffer(runtime.Source_Code_Location)) {
    miMap := make(map[uintptr]_PEModuleInfo, 8, context.temp_allocator)
    defer {
        for _, pemi in miMap {
            os.close(pemi.pdbHandle) // close file
        }
        delete(miMap)
    }
    mdMap := make(map[uintptr]SlimModData, 8, context.temp_allocator)
    defer delete(mdMap)
    //for stackFrame, i in stackTrace {
    for i := len(stackTrace)-1; i>=0; i-=1 {
        stackFrame := stackTrace[i]
        mi, ok := miMap[stackFrame.imgBaseAddr]
        if !ok {
            // PEModuleInfo not found for this module, load them in
            defer miMap[stackFrame.imgBaseAddr] = mi
            nameBuf : [windows.MAX_PATH]u16
            pBuf := &nameBuf[0]
            nameLen := windows.GetModuleFileNameW(windows.HMODULE(stackFrame.imgBaseAddr), pBuf, len(nameBuf))
            path, err := windows.wstring_to_utf8(pBuf, cast(int)nameLen)
            if err != nil {
                continue
            }
            mi.filePath = path
            peFile, peFileErr := os.open(mi.filePath)
            if peFileErr != 0 {
                // skip images that we cannot open
                continue
            }
            defer os.close(peFile)
            dataDirs, dde := parse_pe_data_dirs(os.stream_from_handle(peFile))
            if dataDirs.debug.size > 0 && dde == nil {
                ddEntrys := slice.from_ptr(
                    (^PEDebugDirEntry)((stackFrame.imgBaseAddr) + uintptr(dataDirs.debug.rva)),
                    int(dataDirs.debug.size / size_of(PEDebugDirEntry)),
                )
                for dde in ddEntrys {
                    if dde.debugType != .CodeView do continue
                    if sameProcess {
                        // image is supposed to beloaded, we can just look at the struct in memory
                        pPdbBase := (^PECodeViewInfoPdb70Base)((stackFrame.imgBaseAddr) + uintptr(dde.rawDataAddr))
                        if pPdbBase.cvSignature != PECodeView_Signature_RSDS do continue
                        pPdbPath := (^byte)(uintptr(pPdbBase) + cast(uintptr)size_of(PECodeViewInfoPdb70Base))
                        mi.pdbPath = strings.string_from_null_terminated_ptr(pPdbPath, int(dde.dataSize-size_of(PECodeViewInfoPdb70Base)))
                    } else {
                        // otherwise we need to seek to it on disk
                        peStream := os.stream_from_handle(peFile)
                        if n, err := peStream->impl_seek(i64(dde.pRawData), .Start); err != nil || n != i64(dde.pRawData) do continue
                        buf := make([]byte, int(dde.dataSize))
                        if n, err := peStream->impl_read(buf[:]); err != nil || n != len(buf) {
                            delete(buf)
                            continue
                        }
                        pdbr := make_dummy_reader(buf)
                        pdbInfo := readv(&pdbr, PECodeViewInfoPdb70)
                        if pdbInfo.cvSignature != PECodeView_Signature_RSDS {
                            delete(buf)
                            continue
                        }
                        mi.pdbPath = pdbInfo.name
                    }
                    
                    break
                }
            }
            // TODO: if pdbPath is still not found by now, we should look into other possible directories for them
            pdbFile, pdbErr := os.open(mi.pdbPath)
            if pdbErr != 0 { // try load pdb at the same path as src exe
                toConcatenate := []string {filepath.stem(mi.filePath), ".pdb"}
                mi.pdbPath = strings.concatenate(toConcatenate)
                pdbFile, pdbErr = os.open(mi.pdbPath)
            }
            if pdbErr == 0 {
                mi.pdbHandle = pdbFile
                pdbr := io.Reader{os.stream_from_handle(pdbFile)}
                if streamDir, sdOk := find_stream_dir(pdbr); sdOk {
                    mi.streamDir = streamDir
                    pdbSr := get_stream_reader(&mi.streamDir, PdbStream_Index)
                    pdbHeader, nameMap, pdbFeatures := parse_pdb_stream(&pdbSr)
                    mi.namesStream = get_stream_reader(&mi.streamDir, find_named_stream(nameMap, NamesStream_Name))
                    mi.dbiData = parse_dbi_stream(&mi.streamDir)
                    mi.ipiStream = get_stream_reader(&mi.streamDir, IpiStream_Index)
                    _, ipiOffsetBuf := parse_tpi_stream(&mi.ipiStream, &streamDir)
                    mi.ipiOffsetBuf = ipiOffsetBuf
                }
            }
        }
        pcRva := u32le(stackFrame.progCounter - stackFrame.imgBaseAddr)
        funcRva := u32le(stackFrame.funcBegin)
        if sci := search_for_section_contribution(&mi.dbiData, funcRva); sci >= 0 {
            sc := mi.dbiData.contributions[sci]
            modi := mi.dbiData.modules[sc.module]
            funcOffset := PESectionOffset {
                offset = funcRva - mi.dbiData.sections[sc.secIdx-1].vAddr,
                secIdx = sc.secIdx,
            }
            // address of module's first section contribution in memory. This should 
            // be unique per module across the whole process, making it usable as
            // hash keys for the mod data map
            mdAddress := stackFrame.imgBaseAddr + uintptr(mi.dbiData.sections[modi.secContrOffset.secIdx-1].vAddr) + uintptr(modi.secContrOffset.offset)
            modData, modDataOk := mdMap[mdAddress]
            if !modDataOk {
                modData = parse_mod_stream(&mi.streamDir, &modi)
                mdMap[mdAddress] = modData
            }
            p, lb, l := locate_pc(&modData, funcOffset, pcRva-funcRva)
            scl : runtime.Source_Code_Location
            if lb != nil && lb.nameOffset > 0 {
                mi.namesStream.offset = uint(lb.nameOffset)
                scl.file_path = read_length_prefixed_name(&mi.namesStream)
            } else {
                scl.file_path = modi.moduleName
            }
            if p != nil {
                scl.procedure = p.name
                scl.line = i32(l.lineStart)
                scl.column = i32(l.colStart)
                push_front_rb(srcCodeLocs, scl)

                // locate inline sites
                pParent := p.pSelf
                pcFromFunc := pcRva-funcRva
                inlineSite, src := locate_inline_site(&modData, pParent, pcFromFunc)
                srcLineNum :u32le = 0
                for inlineSite != nil {
                    if src != nil && src.nameOffset > 0 {
                        mi.namesStream.offset = uint(src.nameOffset)
                        scl.file_path = read_length_prefixed_name(&mi.namesStream)
                        srcLineNum = src.srcLineNum
                    } else {
                        scl.file_path = modi.moduleName
                    }
                    lastLine := inlineSite.lines[0]
                    for iline in inlineSite.lines {
                        if iline.offset > pcFromFunc do break
                        lastLine = iline
                    }

                    scl.procedure = "_inlinedFunc" // TODO: parse proc name by cvt info
                    if seek_for_tpi(mi.ipiOffsetBuf, inlineSite.inlinee, &mi.ipiStream) {
                        cvtHeader := readv(&mi.ipiStream, CvtRecordHeader)
                        #partial switch cvtHeader.kind {
                        case .LF_MFUNC_ID:fallthrough // legit because binary structure identical
                        case .LF_FUNC_ID:
                            cvtFuncId := readv(&mi.ipiStream, CvtFuncId)
                            scl.procedure = cvtFuncId.name
                        }
                    }
                    
                    scl.line = i32(lastLine.lineStart + srcLineNum)
                    scl.column = i32(lastLine.colStart)
                    push_front_rb(srcCodeLocs, scl)
                    //fmt.printf("#%v[%v:%v] site found: %v, src: %v\n", srcCodeLocs.len, pParent, pcFromFunc, inlineSite, src)
                    pParent = inlineSite.pSelf
                    inlineSite, src = locate_inline_site(&modData, pParent, pcFromFunc)
                }
            }
        } else {
            scl : runtime.Source_Code_Location
            scl.file_path = mi.filePath // pdb failed to provide us with a valid source file name, fallback to filePath provided by the image
            push_front_rb(srcCodeLocs, scl)
        }
    }
    return
}

_dumpStackTrackMutex : sync.Atomic_Mutex

dump_stack_trace_on_exception :: proc "stdcall" (ExceptionInfo: ^windows.EXCEPTION_POINTERS) -> windows.LONG {
    context = runtime.default_context() // TODO: use a more efficient one-off allocators
    sync.guard(&_dumpStackTrackMutex)
    if ExceptionInfo.ExceptionRecord != nil {
        runtime.print_string("ExceptionType: 0x")
        print_u64_x(u64(ExceptionInfo.ExceptionRecord.ExceptionCode))
        runtime.print_string(", Flags: 0x")
        print_u64_x(u64(ExceptionInfo.ExceptionRecord.ExceptionFlags))
    }
    ctxt := cast(^CONTEXT)ExceptionInfo.ContextRecord
    traceBuf : [64]StackFrame
    traceCount := capture_stack_trace_from_context(ctxt, traceBuf[:])
    runtime.print_string(" Stacktrace:")
    runtime.print_uint(traceCount)
    runtime.print_string("\n")
    srcCodeLocs : RingBuffer(runtime.Source_Code_Location)
    init_rb(&srcCodeLocs, 64)
    parse_stack_trace(traceBuf[:traceCount], true, &srcCodeLocs)
    for i in 0..<srcCodeLocs.len {
        scl := get_rb(&srcCodeLocs, i)
        print_source_code_location(scl)
    }
    return windows.EXCEPTION_CONTINUE_SEARCH
}

print_u64_x :: proc "contextless" (x: u64) #no_bounds_check {
    using runtime
    digits := "0123456789abcdefghijklmnopqrstuvwxyz"
    a: [129]byte
	i := len(a)
	b := u64(16)
	u := x
	for u >= b {
		i -= 1; a[i] = digits[u % b]
		u /= b
	}
	i -= 1; a[i] = digits[u % b]

	os_write(a[i:])
}

print_source_code_location :: proc (using scl: runtime.Source_Code_Location) {
    using runtime
    print_string(file_path)
    when ODIN_ERROR_POS_STYLE == .Unix {
        print_byte(':')
		print_u64(u64(line))
		print_byte(':')
		print_u64(u64(column))
		print_byte(':')
    } else {
        print_byte('(')
		print_u64(u64(line))
		print_byte(':')
		print_u64(u64(column))
		print_byte(')')
    }
    print_string(procedure)
    print_string("()\n")
}
