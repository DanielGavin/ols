package ols_builtin

// Procedures


@builtin len :: proc(array: Array_Type) -> int ---
@builtin cap :: proc(array: Array_Type) -> int ---

@builtin size_of      :: proc($T: typeid) -> int ---
@builtin align_of     :: proc($T: typeid) -> int ---
@builtin type_of      :: proc(x: expr) -> type ---
@builtin type_info_of :: proc($T: typeid) -> ^runtime.Type_Info ---
@builtin typeid_of    :: proc($T: typeid) -> typeid ---

@builtin offset_of_selector :: proc(selector: $T) -> uintptr ---
@builtin offset_of_member   :: proc($T: typeid, member: $M) -> uintptr ---

@builtin offset_of :: proc{offset_of_selector, offset_of_member}

@builtin offset_of_by_string :: proc($T: typeid, member: string) -> uintptr ---

@builtin swizzle :: proc(x: [N]T, indices: ..int) -> [len(indices)]T ---

@builtin complex    :: proc(real, imag: Float) -> Complex_Type ---
@builtin quaternion :: proc(real, imag, jmag, kmag: Float) -> Quaternion_Type --- // fields must be named
@builtin real       :: proc(value: Complex_Or_Quaternion) -> Float ---
@builtin imag       :: proc(value: Complex_Or_Quaternion) -> Float ---
@builtin jmag       :: proc(value: Quaternion) -> Float ---
@builtin kmag       :: proc(value: Quaternion) -> Float ---
@builtin conj       :: proc(value: Complex_Or_Quaternion) -> Complex_Or_Quaternion ---

@builtin min   :: proc(values: ..T) -> T ---
@builtin max   :: proc(values: ..T) -> T ---
@builtin abs   :: proc(value: T) -> T ---
@builtin clamp :: proc(value, minimum, maximum: T) -> T ---

@builtin unreachable :: proc() -> ! ---

@(private="file") _raw_data_slice   :: proc(value: []$E)         -> [^]E    ---
@(private="file") _raw_data_dynamic :: proc(value: [dynamic]$E)  -> [^]E    ---
@(private="file") _raw_data_array   :: proc(value: ^[$N]$E)      -> [^]E    ---
@(private="file") _raw_data_simd    :: proc(value: ^#simd[$N]$E) -> [^]E    ---
@(private="file") _raw_data_string  :: proc(value: string)       -> [^]byte ---
// raw_data is a built-in procedure which returns the underlying data of a built-in data type as a Multi-Pointer.
@builtin raw_data :: proc{_raw_data_slice, _raw_data_dynamic, _raw_data_array, _raw_data_simd, _raw_data_string}

/*
	This is interally from the compiler
*/


@builtin
Odin_Arch_Type :: enum int {
	Unknown,
	amd64,
	i386,
	arm32,
	arm64,
	wasm32,
	wasm64p32,
	riscv64,
}

/*
	An `enum` value indicating the target's CPU architecture.
	Possible values are: `.amd64`, `.i386`, `.arm32`, `.arm64`, `.wasm32`, `.wasm64p32`, and `.riscv64`.
*/
@builtin
ODIN_ARCH: Odin_Arch_Type

/*
	A `string` indicating the target's CPU architecture.
	Possible values are: "amd64", "i386", "arm32", "arm64", "wasm32", "wasm64p32", "riscv64".
*/
@builtin
ODIN_ARCH_STRING: string

@builtin
Odin_Build_Mode_Type :: enum int {
	Executable,
	Dynamic,
	Static,
	Object,
	Assembly,
	LLVM_IR,
}

/*
	An `enum` value indicating the type of compiled output, chosen using `-build-mode`.
	Possible values are: `.Executable`, `.Dynamic`, `.Static`, `.Object`, `.Assembly`, and `.LLVM_IR`.
*/
@builtin
ODIN_BUILD_MODE: Odin_Build_Mode_Type

/*
	A `string` containing the name of the folder that contains the entry point,
	e.g. for `%ODIN_ROOT%/examples/demo`, this would contain `demo`.
*/
@builtin
ODIN_BUILD_PROJECT_NAME: string

/*
	An `i64` containing the time at which the executable was compiled, in nanoseconds.
	This is compatible with the `time.Time` type, i.e. `time.Time{_nsec=ODIN_COMPILE_TIMESTAMP}`
*/
@builtin
ODIN_COMPILE_TIMESTAMP: int

/*
	`true` if the `-debug` command line switch is passed, which enables debug info generation.
*/
@builtin
ODIN_DEBUG: bool

/*
	`true` if the `-default-to-nil-allocator` command line switch is passed,
	which sets the initial `context.allocator` to an allocator that does nothing.
*/
@builtin
ODIN_DEFAULT_TO_NIL_ALLOCATOR: bool

/*
	`true` if the `-default-to-panic-allocator` command line switch is passed,
	which sets the initial `context.allocator` to an allocator that panics if allocated from.
*/
@builtin
ODIN_DEFAULT_TO_PANIC_ALLOCATOR: bool

/*
	`true` if the `-disable-assert` command line switch is passed,
	which removes all calls to `assert` from the program.
*/
@builtin
ODIN_DISABLE_ASSERT: bool

/*
	An `string` indicating the endianness of the target.
	Possible values are: "little" and "big".
*/
@builtin
ODIN_ENDIAN_STRING: string

@builtin
Odin_Endian_Type :: enum int {
	Unknown,
	Little,
	Big,
}

/*
	An `enum` value indicating the endianness of the target.
	Possible values are: `.Little` and `.Big`.
*/
@builtin
ODIN_ENDIAN: Odin_Endian_Type

@builtin
Odin_Error_Pos_Style_Type :: enum int {
	Default = 0,
	Unix    = 1,
}

/*
	An `enum` value set using the `-error-pos-style` switch, indicating the source location style used for compile errors and warnings.
	Possible values are: `.Default` (Odin-style) and `.Unix`.
*/
@builtin
ODIN_ERROR_POS_STYLE: Odin_Error_Pos_Style_Type

/*
	`true` if the `-foreign-error-procedures` command line switch is passed,
	which inhibits generation of runtime error procedures, so that they can be in a separate compilation unit.
*/
@builtin
ODIN_FOREIGN_ERROR_PROCEDURES: bool

/*
	A `string` describing the microarchitecture used for code generation.
	If not set using the `-microarch` command line switch, the compiler will pick a default.
	Possible values include, but are not limited to: "sandybridge", "x86-64-v2".
*/
@builtin
ODIN_MICROARCH_STRING: string

/*
	An `int` value representing the minimum OS version given to the linker, calculated as `major * 10_000 + minor * 100 + revision`.
	If not set using the `-minimum-os-version` command line switch, it defaults to `0`, except on Darwin, where it's `11_00_00`.
*/
@builtin
ODIN_MINIMUM_OS_VERSION: int

/*
	`true` if the `-no-bounds-check` command line switch is passed, which disables bounds checking at runtime.
*/
@builtin
ODIN_NO_BOUNDS_CHECK: bool

/*
	`true` if the `-no-crt` command line switch is passed, which inhibits linking with the C Runtime Library, a.k.a. LibC.
*/
@builtin
ODIN_NO_CRT: bool

/*
	`true` if the `-no-entry-point` command line switch is passed, which makes the declaration of a `main` procedure optional.
*/
@builtin
ODIN_NO_ENTRY_POINT: bool

/*
	`true` if the `-no-rtti` command line switch is passed, which inhibits generation of full Runtime Type Information.
*/
@builtin
ODIN_NO_RTTI: bool

/*
	`true` if the `-no-type-assert` command line switch is passed, which disables type assertion checking program wide.
*/
@builtin
ODIN_NO_TYPE_ASSERT: bool

@builtin
Odin_Optimization_Mode :: enum int {
	None       = -1,
	Minimal    =  0,
	Size       =  1,
	Speed      =  2,
	Aggressive =  3,
}

/*
	An `enum` value indicating the optimization level selected using the `-o` command line switch.
	Possible values are: `.None`, `.Minimal`, `.Size`, `.Speed`, and `.Aggressive`.

	If `ODIN_OPTIMIZATION_MODE` is anything other than `.None` or `.Minimal`, the compiler will also perform a unity build,
	and `ODIN_USE_SEPARATE_MODULES` will be set to `false` as a result.
*/
@builtin
ODIN_OPTIMIZATION_MODE: Odin_Optimization_Mode

@builtin
Odin_OS_Type :: enum int {
	Unknown,
	Windows,
	Darwin,
	Linux,
	Essence,
	FreeBSD,
	OpenBSD,
	NetBSD,
	Haiku,
	WASI,
	JS,
	Orca,
	Freestanding,
}

/*
	An `enum` value indicating what the target operating system is.
*/
@builtin
ODIN_OS: Odin_OS_Type

/*
	A `string` indicating what the target operating system is.
*/
@builtin
ODIN_OS_STRING: string

@builtin
Odin_Platform_Subtarget_Type :: enum int {
	Default,
	iPhone,
	iPhoneSimulator,
	Android,
}

/*
	An `enum` value indicating the platform subtarget, chosen using the `-subtarget` switch.
	Possible values are: `.Default` `.iPhone`, .iPhoneSimulator, and `.Android`.
*/
@builtin
ODIN_PLATFORM_SUBTARGET: Odin_Platform_Subtarget_Type

/*
	A `string` representing the path of the folder containing the Odin compiler,
	relative to which we expect to find the `base` and `core` package collections.
*/
@builtin
ODIN_ROOT: string

@builtin
Odin_Sanitizer_Flag :: enum u32 {
	Address = 0,
	Memory  = 1,
	Thread  = 2,
}

@builtin
Odin_Sanitizer_Flags :: distinct bit_set[Odin_Sanitizer_Flag; u32]

/*
	A `bit_set` indicating the sanitizer flags set using the `-sanitize` command line switch.
	Supported flags are `.Address`, `.Memory`, and `.Thread`.
*/
@builtin
ODIN_SANITIZER_FLAGS: Odin_Sanitizer_Flags

/*
	`true` if the code is being compiled via an invocation of `odin test`.
*/
@builtin
ODIN_TEST: bool

/*
	`true` if built using the experimental Tilde backend.
*/
@builtin
ODIN_TILDE: bool

/*
	`true` by default, meaning each each package is built into its own object file, and then linked together.
	`false` if the `-use-single-module` command line switch to force a unity build is provided.

	If `ODIN_OPTIMIZATION_MODE` is anything other than `.None` or `.Minimal`, the compiler will also perform a unity build,
	and this constant will also be set to `false`.
*/
@builtin
ODIN_USE_SEPARATE_MODULES: bool

/*
	`true` if Valgrind integration is supported on the target.
*/
@builtin
ODIN_VALGRIND_SUPPORT: bool

/*
	A `string` which identifies the compiler being used. The official compiler sets this to `"odin"`.
*/
@builtin
ODIN_VENDOR: string

/*
	A `string` containing the version of the Odin compiler, typically in the format `dev-YYYY-MM`.
*/
@builtin
ODIN_VERSION: string

/*
	A `string` containing the Git hash part of the Odin version.
	Empty if `.git` could not be detected at the time the compiler was built.
*/
@builtin
ODIN_VERSION_HASH: string

@builtin
Odin_Windows_Subsystem_Type :: enum int {
	Unknown,
	Console,
	Windows,
}

/*
	An `enum` set by the `-subsystem` flag, specifying which Windows subsystem the PE file was created for.
	Possible values are:
		`.Unknown` - Default and only value on non-Windows platforms
		`.Console` - Default on Windows
		`.Windows` - Can be used by graphical applications so Windows doesn't open an empty console

	There are some other possible values for e.g. EFI applications, but only Console and Windows are supported.

	See also: https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-image_optional_header64
*/
@builtin
ODIN_WINDOWS_SUBSYSTEM: Odin_Windows_Subsystem_Type

/*
	An `string` set by the `-subsystem` flag, specifying which Windows subsystem the PE file was created for.
	Possible values are:
		"UNKNOWN" - Default and only value on non-Windows platforms
		"CONSOLE" - Default on Windows
		"WINDOWS" - Can be used by graphical applications so Windows doesn't open an empty console

	There are some other possible values for e.g. EFI applications, but only Console and Windows are supported.

	See also: https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-image_optional_header64
*/
@builtin
ODIN_WINDOWS_SUBSYSTEM_STRING: string

/*
	`true` if LLVM supports the f16 type.
*/
@builtin
__ODIN_LLVM_F16_SUPPORTED: bool
