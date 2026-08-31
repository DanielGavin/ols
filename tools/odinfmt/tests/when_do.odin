package when_do

// A `do` body has no closing brace, so flattening this chain produces invalid Odin.
current_platform_string :: proc() -> string {
	when ODIN_OS == .Darwin do return "darwin"
	else when ODIN_OS == .Linux do return "linux"
	else when ODIN_OS == .Windows do return "win32"
	else do return "unknown"
}
