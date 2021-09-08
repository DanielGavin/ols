package ols_builtin

// Procedures
len :: proc(array: Array_Type) -> int ---
cap :: proc(array: Array_Type) -> int ---

size_of      :: proc($T: typeid) -> int ---
align_of     :: proc($T: typeid) -> int ---
offset_of    :: proc($T: typeid) -> uintptr ---
type_of      :: proc(x: expr) -> type ---
type_info_of :: proc($T: typeid) -> ^runtime.Type_Info ---
typeid_of    :: proc($T: typeid) -> typeid ---

swizzle :: proc(x: [N]T, indices: ..int) -> [len(indices)]T ---

complex    :: proc(real, imag: Float) -> Complex_Type ---
quaternion :: proc(real, imag, jmag, kmag: Float) -> Quaternion_Type ---
real       :: proc(value: Complex_Or_Quaternion) -> Float ---
imag       :: proc(value: Complex_Or_Quaternion) -> Float ---
jmag       :: proc(value: Quaternion) -> Float ---
kmag       :: proc(value: Quaternion) -> Float ---
conj       :: proc(value: Complex_Or_Quaternion) -> Complex_Or_Quaternion ---

min   :: proc(values: ..T) -> T ---
max   :: proc(values: ..T) -> T ---
abs   :: proc(value: T) -> T ---
clamp :: proc(value, minimum, maximum: T) -> T ---