package common

import "core:fmt"

//ported version of https://llvm.org/doxygen/SHa1_8cpp_source.html

rol :: proc (number: u32, bits: u32) -> u32 {
	return number << bits | number >> (32 - bits);
}

blk0 :: proc (buf: []u32, i: int) -> u32 {
	return buf[i];
}

blk :: proc (buf: []u32, i: int) -> u32 {
	buf[i & 15] = rol(buf[(i + 13) & 15] ~ buf[(i + 8) & 15] ~ buf[(i + 2) & 15] ~
		buf[i & 15], 1);

	return buf[i & 15];
}

r0 :: proc (a: ^u32, b: ^u32, c: ^u32, d: ^u32, e: ^u32, i: int, buf: []u32) {
	e^ += ((b^ & (c^ ~ d^)) ~ d^) + blk0(buf, i) + 0x5a827999 + rol(a^, 5);
	b^ = rol(b^, 30);
}

r1 :: proc (a: ^u32, b: ^u32, c: ^u32, d: ^u32, e: ^u32, i: int, buf: []u32) {
	e^ += ((b^ & (c^ ~ d^)) ~ d^) + blk(buf, i) + 0x5a827999 + rol(a^, 5);
	b^ += rol(b^, 30);
}

r2 :: proc (a: ^u32, b: ^u32, c: ^u32, d: ^u32, e: ^u32, i: int, buf: []u32) {
	e^ += (b^ ~ c^ ~ d^) + blk(buf, i) + 0x6ed9eba1 + rol(a^, 5);
	b^ += rol(b^, 30);
}

r3 :: proc (a: ^u32, b: ^u32, c: ^u32, d: ^u32, e: ^u32, i: int, buf: []u32) {
	e^ += (((b^ | c^) & d^) | (b^ & c^)) + blk(buf, i) + 0x8F1bbcdc + rol(a^, 5);
	b^ += rol(b^, 30);
}

r4 :: proc (a: ^u32, b: ^u32, c: ^u32, d: ^u32, e: ^u32, i: int, buf: []u32) {
	e^ += (b^ ~ c^ ~ d^) + blk(buf, i) + 0xca62c1d6 + rol(a^, 5);
	b^ += rol(b^, 30);
}

SHA1_K0  :: 0x5a827999;
SHA1_K20 :: 0x6ed9eba1;
SHA1_K40 :: 0x8f1bbcdc;
SHA1_K60 :: 0xca62c1d6;

SEED_0 :: 0x67452301;
SEED_1 :: 0xefcdab89;
SEED_2 :: 0x98badcfe;
SEED_3 :: 0x10325476;
SEED_4 :: 0xc3d2e1f0;

BLOCK_LENGTH :: 64;
HASH_LENGTH  :: 20;

Sha1context :: struct {
	buf:        struct #raw_union {
		c: [BLOCK_LENGTH]byte,
		l: [BLOCK_LENGTH / 4]u32,
	},
	state:      [HASH_LENGTH / 4]u32,
	byte_count: u32,
	buf_offset: u8,
}

sha1_init :: proc (state_context: ^Sha1context) {
	state_context.state[0]   = SEED_0;
	state_context.state[1]   = SEED_1;
	state_context.state[2]   = SEED_2;
	state_context.state[3]   = SEED_3;
	state_context.state[4]   = SEED_4;
	state_context.byte_count = 0;
	state_context.buf_offset = 0;
}

sha1_hash_block :: proc (state_context: ^Sha1context) {
	a := state_context.state[0];
	b := state_context.state[1];
	c := state_context.state[2];
	d := state_context.state[3];
	e := state_context.state[4];

	// 4 rounds of 20 operations each. loop unrolled.
	r0(&a, &b, &c, &d, &e, 0, state_context.buf.l[:]);
	r0(&e, &a, &b, &c, &d, 1, state_context.buf.l[:]);
	r0(&d, &e, &a, &b, &c, 2, state_context.buf.l[:]);
	r0(&c, &d, &e, &a, &b, 3, state_context.buf.l[:]);
	r0(&b, &c, &d, &e, &a, 4, state_context.buf.l[:]);
	r0(&a, &b, &c, &d, &e, 5, state_context.buf.l[:]);
	r0(&e, &a, &b, &c, &d, 6, state_context.buf.l[:]);
	r0(&d, &e, &a, &b, &c, 7, state_context.buf.l[:]);
	r0(&c, &d, &e, &a, &b, 8, state_context.buf.l[:]);
	r0(&b, &c, &d, &e, &a, 9, state_context.buf.l[:]);
	r0(&a, &b, &c, &d, &e, 10, state_context.buf.l[:]);
	r0(&e, &a, &b, &c, &d, 11, state_context.buf.l[:]);
	r0(&d, &e, &a, &b, &c, 12, state_context.buf.l[:]);
	r0(&c, &d, &e, &a, &b, 13, state_context.buf.l[:]);
	r0(&b, &c, &d, &e, &a, 14, state_context.buf.l[:]);
	r0(&a, &b, &c, &d, &e, 15, state_context.buf.l[:]);
	r1(&e, &a, &b, &c, &d, 16, state_context.buf.l[:]);
	r1(&d, &e, &a, &b, &c, 17, state_context.buf.l[:]);
	r1(&c, &d, &e, &a, &b, 18, state_context.buf.l[:]);
	r1(&b, &c, &d, &e, &a, 19, state_context.buf.l[:]);

	r2(&a, &b, &c, &d, &e, 20, state_context.buf.l[:]);
	r2(&e, &a, &b, &c, &d, 21, state_context.buf.l[:]);
	r2(&d, &e, &a, &b, &c, 22, state_context.buf.l[:]);
	r2(&c, &d, &e, &a, &b, 23, state_context.buf.l[:]);
	r2(&b, &c, &d, &e, &a, 24, state_context.buf.l[:]);
	r2(&a, &b, &c, &d, &e, 25, state_context.buf.l[:]);
	r2(&e, &a, &b, &c, &d, 26, state_context.buf.l[:]);
	r2(&d, &e, &a, &b, &c, 27, state_context.buf.l[:]);
	r2(&c, &d, &e, &a, &b, 28, state_context.buf.l[:]);
	r2(&b, &c, &d, &e, &a, 29, state_context.buf.l[:]);
	r2(&a, &b, &c, &d, &e, 30, state_context.buf.l[:]);
	r2(&e, &a, &b, &c, &d, 31, state_context.buf.l[:]);
	r2(&d, &e, &a, &b, &c, 32, state_context.buf.l[:]);
	r2(&c, &d, &e, &a, &b, 33, state_context.buf.l[:]);
	r2(&b, &c, &d, &e, &a, 34, state_context.buf.l[:]);
	r2(&a, &b, &c, &d, &e, 35, state_context.buf.l[:]);
	r2(&e, &a, &b, &c, &d, 36, state_context.buf.l[:]);
	r2(&d, &e, &a, &b, &c, 37, state_context.buf.l[:]);
	r2(&c, &d, &e, &a, &b, 38, state_context.buf.l[:]);
	r2(&b, &c, &d, &e, &a, 39, state_context.buf.l[:]);

	r3(&a, &b, &c, &d, &e, 40, state_context.buf.l[:]);
	r3(&e, &a, &b, &c, &d, 41, state_context.buf.l[:]);
	r3(&d, &e, &a, &b, &c, 42, state_context.buf.l[:]);
	r3(&c, &d, &e, &a, &b, 43, state_context.buf.l[:]);
	r3(&b, &c, &d, &e, &a, 44, state_context.buf.l[:]);
	r3(&a, &b, &c, &d, &e, 45, state_context.buf.l[:]);
	r3(&e, &a, &b, &c, &d, 46, state_context.buf.l[:]);
	r3(&d, &e, &a, &b, &c, 47, state_context.buf.l[:]);
	r3(&c, &d, &e, &a, &b, 48, state_context.buf.l[:]);
	r3(&b, &c, &d, &e, &a, 49, state_context.buf.l[:]);
	r3(&a, &b, &c, &d, &e, 50, state_context.buf.l[:]);
	r3(&e, &a, &b, &c, &d, 51, state_context.buf.l[:]);
	r3(&d, &e, &a, &b, &c, 52, state_context.buf.l[:]);
	r3(&c, &d, &e, &a, &b, 53, state_context.buf.l[:]);
	r3(&b, &c, &d, &e, &a, 54, state_context.buf.l[:]);
	r3(&a, &b, &c, &d, &e, 55, state_context.buf.l[:]);
	r3(&e, &a, &b, &c, &d, 56, state_context.buf.l[:]);
	r3(&d, &e, &a, &b, &c, 57, state_context.buf.l[:]);
	r3(&c, &d, &e, &a, &b, 58, state_context.buf.l[:]);
	r3(&b, &c, &d, &e, &a, 59, state_context.buf.l[:]);

	r4(&a, &b, &c, &d, &e, 60, state_context.buf.l[:]);
	r4(&e, &a, &b, &c, &d, 61, state_context.buf.l[:]);
	r4(&d, &e, &a, &b, &c, 62, state_context.buf.l[:]);
	r4(&c, &d, &e, &a, &b, 63, state_context.buf.l[:]);
	r4(&b, &c, &d, &e, &a, 64, state_context.buf.l[:]);
	r4(&a, &b, &c, &d, &e, 65, state_context.buf.l[:]);
	r4(&e, &a, &b, &c, &d, 66, state_context.buf.l[:]);
	r4(&d, &e, &a, &b, &c, 67, state_context.buf.l[:]);
	r4(&c, &d, &e, &a, &b, 68, state_context.buf.l[:]);
	r4(&b, &c, &d, &e, &a, 69, state_context.buf.l[:]);
	r4(&a, &b, &c, &d, &e, 70, state_context.buf.l[:]);
	r4(&e, &a, &b, &c, &d, 71, state_context.buf.l[:]);
	r4(&d, &e, &a, &b, &c, 72, state_context.buf.l[:]);
	r4(&c, &d, &e, &a, &b, 73, state_context.buf.l[:]);
	r4(&b, &c, &d, &e, &a, 74, state_context.buf.l[:]);
	r4(&a, &b, &c, &d, &e, 75, state_context.buf.l[:]);
	r4(&e, &a, &b, &c, &d, 76, state_context.buf.l[:]);
	r4(&d, &e, &a, &b, &c, 77, state_context.buf.l[:]);
	r4(&c, &d, &e, &a, &b, 78, state_context.buf.l[:]);
	r4(&b, &c, &d, &e, &a, 79, state_context.buf.l[:]);

	state_context.state[0] += a;
	state_context.state[1] += b;
	state_context.state[2] += c;
	state_context.state[3] += d;
	state_context.state[4] += e;
}

sha1_add_uncounted :: proc (state_context: ^Sha1context, data: byte) {

	when ODIN_ENDIAN == .Big {
		state_context.buf.c[state_context.buf_offset] = data;
	} else

	{
		state_context.buf.c[state_context.buf_offset ~ 3] = data;
	}

	state_context.buf_offset += 1;

	if state_context.buf_offset == BLOCK_LENGTH {
		sha1_hash_block(state_context);
		state_context.buf_offset = 0;
	}
}

sha1_write_byte :: proc (state_context: ^Sha1context, data: byte) {
	state_context.byte_count += 1;
	sha1_add_uncounted(state_context, data);
}

sha1_update :: proc (state_context: ^Sha1context, data: []byte) {

	state_context.byte_count += cast(u32)len(data);

	current_data := data;

	if state_context.buf_offset > 0 {
		remainder := min(len(current_data), BLOCK_LENGTH - cast(int)state_context.buf_offset);

		for i := 0; i < remainder; i += 1 {
			sha1_add_uncounted(state_context, current_data[i]);
		}

		current_data = current_data[remainder - 1:];
	}

	for len(current_data) >= BLOCK_LENGTH {
		assert(state_context.buf_offset == 0);
		assert(BLOCK_LENGTH % 4 == 0);

		BLOCK_LENGTH_32 :: BLOCK_LENGTH / 4;

		for i := 0; i < BLOCK_LENGTH_32; i += 1 {
			n := (transmute([]u32)current_data)[i];

			state_context.buf.l[i] = (((n & 0xFF) << 24) |
				((n & 0xFF00) << 8) |
				((n & 0xFF0000) >> 8) |
				((n & 0xFF000000) >> 24));
		}

		sha1_hash_block(state_context);

		current_data = current_data[BLOCK_LENGTH - 1:];
	}

	for c in current_data {
		sha1_add_uncounted(state_context, c);
	}
}

sha1_pad :: proc (state_context: ^Sha1context) {

	sha1_add_uncounted(state_context, 0x80);

	for state_context.buf_offset != 56 {
		sha1_add_uncounted(state_context, 0x00);
	}

	sha1_add_uncounted(state_context, 0); // We're only using 32 bit lengths
	sha1_add_uncounted(state_context, 0); // But SHA-1 supports 64 bit lengths
	sha1_add_uncounted(state_context, 0); // So zero pad the top bits
	sha1_add_uncounted(state_context, cast(u8)(state_context.byte_count >> 29)); // Shifting to multiply by 8
	sha1_add_uncounted(state_context, cast(u8)(state_context.byte_count >> 21)); // as SHA-1 supports bitstreams as well as
	sha1_add_uncounted(state_context, cast(u8)(state_context.byte_count >> 13)); // byte.
	sha1_add_uncounted(state_context, cast(u8)(state_context.byte_count >> 5));
	sha1_add_uncounted(state_context, cast(u8)(state_context.byte_count << 3));
}
sha1_final :: proc (state_context: ^Sha1context, result: ^[5]u32) {

	sha1_pad(state_context);

	when ODIN_ENDIAN == .Big {

		for i := 0; i < 5; i += 1 {
			result[i] = state_context.state[i];
		}
	} else

	{
		for i := 0; i < 5; i += 1 {
			result[i] = (((state_context.state[i]) << 24) & 0xff000000) |
				(((state_context.state[i]) << 8) & 0x00ff0000) |
				(((state_context.state[i]) >> 8) & 0x0000ff00) |
				(((state_context.state[i]) >> 24) & 0x000000ff);
		}
	}
}

sha1_hash :: proc (data: []byte) -> [20]byte {

	sha1_context: Sha1context;
	sha1_init(&sha1_context);
	sha1_update(&sha1_context, data);

	result: [20]byte;

	sha1_final(&sha1_context, cast(^[5]u32)&result);

	ret: [20]byte;

	copy(ret[:], result[:]);

	return ret;
}
