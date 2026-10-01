package tests

import "core:strings"
import "core:testing"

import test "src:testing"

@(private = "file")
LAYOUT_TYPES :: `Basic :: struct { a: u8, b: u64, c: u16 }
Nested :: struct { a: bool, inner: Basic, z: u8 }
Ptrs :: struct { p: ^int, s: []u8, d: [dynamic]int, m: map[string]int, str: string, c: cstring, r: rawptr, a: any, t: typeid, mp: [^]u8, f: proc() }
Aligned :: struct #align(32) { a: u8 }
MinAlign :: struct #min_field_align(4) { a: u8, b: u16 }
MaxAlign :: struct #max_field_align(2) { a: u8, b: u64 }
Packed :: struct #packed { a: u8, b: u64 }
Raw :: struct #raw_union { a: u8, b: u64, c: [3]u32 }
Empty :: struct {}
Arr :: struct { a: [3]f32, b: [N]u16, c: [N * 2 + 1]u8 }
EnumArr :: struct { a: [E3]u32, b: #sparse[E10]u32 }
Floats :: struct { h: f16, c: complex32, q: quaternion128, x: complex128, big: i128 }
U1 :: union { u8, u16 }
U2 :: union { u64, [3]u8 }
U3 :: union #no_nil { u8, u16 }
U4 :: union { ^int }
U5 :: union { i128, u8 }
U7 :: union { [5]u8, u16 }
U8 :: union #align(16) { u8 }
U9 :: union #align(16) { ^int }
U10 :: union #align(16) { [9]u8 }
U12 :: union #align(2) { u64, u8 }
U11 :: union { []int }
Enums :: struct { e: E3, s: Small, bs: bit_set[E3], bs2: bit_set[E10], bs3: bit_set[0..<33], bs4: bit_set['a'..='z'], bs5: bit_set[E3; u32] }
Mats :: struct { a: matrix[3, 3]f32, b: matrix[4, 4]f64, c: matrix[2, 3]f32 }
Simd :: struct { a: #simd[4]f32, b: #simd[8]f32, c: #simd[2]f64 }
FixDyn :: struct { a: [dynamic; 4]u8, b: [dynamic; 3]u64 }
Soa :: struct { a: #soa[]V3, b: #soa[4]V3, c: #soa[dynamic]V3 }
V3 :: struct { x, y, z: f32 }
BF :: bit_field u32 { a: u8 | 3, b: u16 | 9 }
WithBF :: struct { a: u8, bf: BF }
Gen :: struct($T: typeid) { a: u8, v: T }
GenUse :: struct { g: Gen(u64), m: Maybe(int), mp: Maybe(^int) }
Distinct :: distinct Basic
Alias :: [4]Basic
Small :: enum u8 { A, B }
SizeOf :: struct { a: [size_of(Basic)]u8 }
UsingS :: struct { using base: Basic, extra: u32 }`

@(private = "file")
LAYOUT_HEADER :: `package test

N :: 5
E3 :: enum { A, B, C }
E10 :: enum { A = 10, B = 20 }
Maybe :: union($T: typeid) { T }
`

@(private = "file")
expect_type_layout :: proc(t: ^testing.T, name: string, expected: string) {
	decl := strings.concatenate({"\n", name, " ::"}, context.temp_allocator)
	types := strings.concatenate({"\n", LAYOUT_TYPES}, context.temp_allocator)
	with_cursor, _ := strings.replace(
		types,
		decl,
		strings.concatenate({"\n", name[:1], "{*}", name[1:], " ::"}, context.temp_allocator),
		1,
		context.temp_allocator,
	)
	source := test.Source {
		main = strings.concatenate({LAYOUT_HEADER, with_cursor}, context.temp_allocator),
	}
	source.config.enable_hover_layout = true
	test.expect_hover_contains(t, &source, expected)
}

@(test)
hover_layout_basic :: proc(t: ^testing.T) {
	expect_type_layout(t, "Basic", "size=24, align=8")
}

@(test)
hover_layout_nested :: proc(t: ^testing.T) {
	expect_type_layout(t, "Nested", "size=40, align=8")
}

@(test)
hover_layout_ptrs :: proc(t: ^testing.T) {
	expect_type_layout(t, "Ptrs", "size=168, align=8")
}

@(test)
hover_layout_aligned :: proc(t: ^testing.T) {
	expect_type_layout(t, "Aligned", "size=32, align=32")
}

@(test)
hover_layout_minalign :: proc(t: ^testing.T) {
	expect_type_layout(t, "MinAlign", "size=8, align=4")
}

@(test)
hover_layout_maxalign :: proc(t: ^testing.T) {
	expect_type_layout(t, "MaxAlign", "size=10, align=2")
}

@(test)
hover_layout_packed :: proc(t: ^testing.T) {
	expect_type_layout(t, "Packed", "size=9, align=1")
}

@(test)
hover_layout_raw :: proc(t: ^testing.T) {
	expect_type_layout(t, "Raw", "size=16, align=8")
}

@(test)
hover_layout_empty :: proc(t: ^testing.T) {
	expect_type_layout(t, "Empty", "size=0, align=1")
}

@(test)
hover_layout_arr :: proc(t: ^testing.T) {
	expect_type_layout(t, "Arr", "size=36, align=4")
}

@(test)
hover_layout_enumarr :: proc(t: ^testing.T) {
	expect_type_layout(t, "EnumArr", "size=56, align=4")
}

@(test)
hover_layout_floats :: proc(t: ^testing.T) {
	expect_type_layout(t, "Floats", "size=64, align=16")
}

@(test)
hover_layout_u1 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U1", "size=4, align=2")
}

@(test)
hover_layout_u2 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U2", "size=16, align=8")
}

@(test)
hover_layout_u3 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U3", "size=4, align=2")
}

@(test)
hover_layout_u4 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U4", "size=8, align=8")
}

@(test)
hover_layout_u5 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U5", "size=32, align=16")
}

@(test)
hover_layout_u7 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U7", "size=8, align=2")
}

@(test)
hover_layout_u8 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U8", "size=16, align=16")
}

@(test)
hover_layout_u9 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U9", "size=16, align=16")
}

@(test)
hover_layout_u10 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U10", "size=32, align=16")
}

@(test)
hover_layout_u12 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U12", "size=10, align=2")
}

@(test)
hover_layout_u11 :: proc(t: ^testing.T) {
	expect_type_layout(t, "U11", "size=24, align=8")
}

@(test)
hover_layout_enums :: proc(t: ^testing.T) {
	expect_type_layout(t, "Enums", "size=32, align=8")
}

@(test)
hover_layout_mats :: proc(t: ^testing.T) {
	expect_type_layout(t, "Mats", "size=192, align=8")
}

@(test)
hover_layout_simd :: proc(t: ^testing.T) {
	expect_type_layout(t, "Simd", "size=64, align=16")
}

@(test)
hover_layout_fixdyn :: proc(t: ^testing.T) {
	expect_type_layout(t, "FixDyn", "size=48, align=8")
}

@(test)
hover_layout_soa :: proc(t: ^testing.T) {
	expect_type_layout(t, "Soa", "size=136, align=8")
}

@(test)
hover_layout_v3 :: proc(t: ^testing.T) {
	expect_type_layout(t, "V3", "size=12, align=4")
}

@(test)
hover_layout_bf :: proc(t: ^testing.T) {
	expect_type_layout(t, "BF", "size=4, align=4")
}

@(test)
hover_layout_withbf :: proc(t: ^testing.T) {
	expect_type_layout(t, "WithBF", "size=8, align=4")
}

@(test)
hover_layout_genuse :: proc(t: ^testing.T) {
	expect_type_layout(t, "GenUse", "size=40, align=8")
}

@(test)
hover_layout_distinct :: proc(t: ^testing.T) {
	expect_type_layout(t, "Distinct", "size=24, align=8")
}

@(test)
hover_layout_alias :: proc(t: ^testing.T) {
	expect_type_layout(t, "Alias", "size=96, align=8")
}

@(test)
hover_layout_small :: proc(t: ^testing.T) {
	expect_type_layout(t, "Small", "size=1, align=1")
}

@(test)
hover_layout_sizeof :: proc(t: ^testing.T) {
	expect_type_layout(t, "SizeOf", "size=24, align=1")
}

@(test)
hover_layout_usings :: proc(t: ^testing.T) {
	expect_type_layout(t, "UsingS", "size=32, align=8")
}

@(test)
hover_layout_struct_field_comments :: proc(t: ^testing.T) {
	expect_type_layout(
		t,
		"Basic",
		"test.Basic :: struct { // size=24, align=8, padding=13\n\ta: u8,  // size=1, offset=0 (+7 padding)\n\tb: u64, // size=8, offset=8\n\tc: u16, // size=2, offset=16 (+6 padding)\n}",
	)
}

@(test)
hover_layout_field_offset :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Basic :: struct { a: u8, b: u64, c: u16 }
		main :: proc() {
			x: Basic
			x.c{*} = 1
		}
		`,
	}
	source.config.enable_hover_layout = true
	test.expect_hover_contains(t, &source, "Basic.c: u16 // size=2, offset=16")
}

@(test)
hover_layout_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Basic :: struct { a: u8, b: u64, c: u16 }
		main :: proc() {
			x{*}: [3]Basic
		}
		`,
	}
	source.config.enable_hover_layout = true
	test.expect_hover_contains(t, &source, "size=72, align=8")
}

@(test)
hover_layout_disabled :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Bas{*}ic :: struct { a: u8, b: u64 }
		`,
	}
	test.expect_hover(t, &source, "test.Basic :: struct {\n\ta: u8,\n\tb: u64,\n}")
}

@(test)
hover_layout_field_comment_kept :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Bas{*}ic :: struct {
			a: u8, // the a
			long_name: u64,
		}
		`,
	}
	source.config.enable_hover_layout = true
	test.expect_hover(
		t,
		&source,
		"test.Basic :: struct { // size=16, align=8, padding=7\n\ta:         u8,  // size=1, offset=0 (+7 padding) // the a\n\tlong_name: u64, // size=8, offset=8\n}",
	)
}

@(test)
hover_layout_foreign_package_alias :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "pkg_c", source = `package pkg_c
		Int :: distinct i16
		`})
	append(
		&packages,
		test.Package {
			pkg = "pkg_b",
			source = `package pkg_b
		import c "pkg_c"
		E :: enum c.Int { A, B }
		BF :: bit_field c.Int { x: u8 | 4 }
		S :: struct #align(size_of(c.Int) * 4) { a: u8 }
		`,
		},
	)

	source := test.Source {
		main     = `package test
		import "pkg_b"
		F{*}oo :: struct { e: pkg_b.E, bf: pkg_b.BF, s: pkg_b.S }
		`,
		packages = packages[:],
	}
	source.config.enable_hover_layout = true
	test.expect_hover_contains(t, &source, "size=16, align=8")
}
