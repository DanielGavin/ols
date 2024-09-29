package common

import "core:fmt"
import "core:strings"

/*
	Ported from https://github.com/llvm/llvm-project/blob/master/clang-tools-extra/clangd/FuzzyMatch.cpp
*/

max_pattern :: 63
max_word :: 256

awful_score: int = -(1 << 13)
perfect_bonus :: 4
miss :: 0
match :: 1

FuzzyCharTypeSet :: u8

//do bitfield instead
FuzzyScoreInfo :: struct {
	score: int,
	prev:  int,
}

FuzzyCharRole :: enum (u8) {
	Unknown   = 0, // Stray control characters or impossible states.
	Tail      = 1, // Part of a word segment, but not the first character.
	Head      = 2, // The first character of a word segment.
	Separator = 3, // Punctuation characters that separate word segments.
}

FuzzyCharType :: enum (u8) {
	Empty       = 0, // Before-the-start and after-the-end (and control chars).
	Lower       = 1, // Lowercase letters, digits, and non-ASCII bytes.
	Upper       = 2, // Uppercase letters.
	Punctuation = 3, // ASCII punctuation (including Space)
}

FuzzyMatcher :: struct {
	pattern:          string,
	word:             string,
	lower_pattern:    string,
	lower_word:       string,
	scores:           [max_pattern + 1][max_word + 1][2]FuzzyScoreInfo,
	pattern_count:    int,
	pattern_type_set: FuzzyCharTypeSet,
	word_type_set:    FuzzyCharTypeSet,
	pattern_role:     [max_pattern]FuzzyCharRole,
	word_count:       int,
	score_scale:      f32,
	word_role:        [max_word]FuzzyCharRole,
}

//odinfmt: disable
char_roles: []u8 = {
	// clang-format off
	//         Curr= Empty Lower Upper Separ
	/*Prev=Empty */0x00,0xaa,0xaa,0xff, // At start, Lower|Upper->Head
	/*Prev=Lower */0x00,0x55,0xaa,0xff, // In word, Upper->Head;Lower->Tail
	/*Prev=Upper */0x00,0x55,0x59,0xff, // Ditto, but U(U)U->Tail
	/*Prev=Separ */0x00,0xaa,0xaa,0xff, // After separator, like at start
	// clang-format on
}

char_types: []u8 = {
	0x00,0x00,0x00,0x00, // Control characters
	0x00,0x00,0x00,0x00, // Control characters
	0xff,0xff,0xff,0xff, // Punctuation
	0x55,0x55,0xf5,0xff, // Numbers->Lower, more Punctuation.
	0xab,0xaa,0xaa,0xaa, // @ and A-O
	0xaa,0xaa,0xea,0xff, // P-Z, more Punctuation.
	0x57,0x55,0x55,0x55, // ` and a-o
	0x55,0x55,0xd5,0x3f, // p-z, Punctuation, DEL.
	0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55, // Bytes over 127 -> Lower.
	0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55, // (probably UTF-8).
	0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55,
	0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55,
}
//odinfmt: enable


make_fuzzy_matcher :: proc(pattern: string, allocator := context.temp_allocator) -> ^FuzzyMatcher {
	matcher := new(FuzzyMatcher, allocator)

	matcher.pattern_count = min(len(pattern), max_pattern)
	matcher.score_scale = matcher.pattern_count > 0 ? 1 / cast(f32)(perfect_bonus * matcher.pattern_count) : 0
	matcher.pattern = pattern[0:matcher.pattern_count]
	matcher.lower_pattern = strings.to_lower(matcher.pattern, context.temp_allocator)

	score_info_miss: FuzzyScoreInfo
	score_info_miss.score = 0
	score_info_miss.prev = miss

	matcher.scores[0][0][miss] = score_info_miss

	score_info_match: FuzzyScoreInfo
	score_info_match.score = awful_score
	score_info_match.prev = match

	matcher.scores[0][0][match] = score_info_match

	for p := 0; p < matcher.pattern_count; p += 1 {

		for w := 0; w < p; w += 1 {

			for a := 0; a < 2; a += 1 {
				score_info: FuzzyScoreInfo
				score_info.score = awful_score
				score_info.prev = miss
				matcher.scores[p][w][a] = score_info
				ref := matcher.pattern_role[:matcher.pattern_count]
				matcher.pattern_type_set = fuzzy_calculate_roles(matcher.pattern, &ref)
			}
		}
	}

	return matcher
}

fuzzy_to_acronym :: proc(word: string) -> (string, bool) {
	builder := strings.builder_make(context.temp_allocator)

	if len(word) <= 1 {
		return "", false
	}

	i := 1
	last_char := word[0]

	strings.write_byte(&builder, last_char)

	for i < len(word) {

		if last_char == '_' {
			strings.write_byte(&builder, word[i])
		}

		last_char = word[i]

		i += 1
	}

	str := strings.to_string(builder)

	if len(str) <= 1 {
		return "", false
	}

	return str, true
}
//changed from bool to int because of a linux bug - 10.05.2021
fuzzy_match :: proc(matcher: ^FuzzyMatcher, word: string) -> (f32, int) {

	if !fuzzy_init(matcher, word) {
		return 0, 0
	}

	if matcher.pattern_count <= 0 {
		return 1, 1
	}

	if acronym, ok := fuzzy_to_acronym(word); ok {
		if acronym == matcher.pattern {
			return 20, 1
		}
	}

	fuzzy_build_graph(matcher)

	best := max(
		cast(int)matcher.scores[matcher.pattern_count][matcher.word_count][miss].score,
		cast(int)matcher.scores[matcher.pattern_count][matcher.word_count][match].score,
	)

	if fuzzy_is_awful(best) {
		return 0.0, 0
	}

	score := matcher.score_scale * min(perfect_bonus * cast(f32)matcher.pattern_count, cast(f32)max(0, best))

	if matcher.word_count == matcher.pattern_count {
		score *= 2
	}

	return score, 1
}

fuzzy_is_awful :: proc(s: int) -> bool {
	return s < awful_score / 2
}

fuzzy_calculate_roles :: proc(text: string, roles: ^[]FuzzyCharRole) -> FuzzyCharTypeSet {
	if len(text) != len(roles) {
		return 0
	}

	if len(text) == 0 {
		return 0
	}

	type: FuzzyCharType = cast(FuzzyCharType)fuzzy_packed_lookup(char_types, cast(uint)text[0])

	type_set: FuzzyCharTypeSet = cast(u8)(1 << cast(uint)type)

	types := type

	for i := 0; i < len(text) - 1; i += 1 {
		type = cast(FuzzyCharType)fuzzy_packed_lookup(char_types, cast(uint)text[i + 1])
		type_set |= 1 << cast(uint)type

		fuzzy_rotate(type, &types)

		roles[i] = cast(FuzzyCharRole)fuzzy_packed_lookup(char_roles, cast(uint)types)
	}

	fuzzy_rotate(.Empty, &types)

	roles[len(text) - 1] = cast(FuzzyCharRole)fuzzy_packed_lookup(char_roles, cast(uint)types)

	return type_set
}

fuzzy_rotate :: proc(t: FuzzyCharType, types: ^FuzzyCharType) {
	types^ = cast(FuzzyCharType)(((cast(uint)types^ << 2) | cast(uint)t) & 0x3f)
}

fuzzy_packed_lookup :: proc(data: $A/[]$T, i: uint) -> T {
	return (data[i >> 2] >> ((i & 3) * 2)) & 3
}

fuzzy_init :: proc(matcher: ^FuzzyMatcher, word: string) -> bool {
	matcher.word = word
	matcher.word_count = min(max_word, len(matcher.word))

	if matcher.pattern_count > matcher.word_count {
		return false
	}

	if matcher.pattern_count == 0 {
		return true
	}

	matcher.lower_word = strings.to_lower(word, context.temp_allocator)

	w, p := 0, 0

	for ; p != matcher.pattern_count; w += 1 {
		if w == matcher.word_count {
			return false
		}

		if matcher.lower_word[w] == matcher.lower_pattern[p] {
			p += 1
		}
	}

	ref := matcher.word_role[:matcher.word_count]

	matcher.word_type_set = fuzzy_calculate_roles(word, &ref)

	return true
}

fuzzy_skip_penalty :: proc(matcher: ^FuzzyMatcher, w: int) -> int {
	if w == 0 { 	// Skipping the first character.
		return 3
	}

	if matcher.word_role[w] == .Head { 	// Skipping a segment.
		return 1
	}

	return 0
}

fuzzy_build_graph :: proc(matcher: ^FuzzyMatcher) {
	for w := 0; w < matcher.word_count; w += 1 {

		s: FuzzyScoreInfo

		score := cast(int)matcher.scores[0][w][miss].score
		penalty := fuzzy_skip_penalty(matcher, w)
		sum := score - penalty

		s.score = sum
		s.prev = miss

		matcher.scores[0][w + 1][miss] = s

		s.score = awful_score
		s.prev = miss

		matcher.scores[0][w + 1][match] = s
	}

	for p := 0; p < matcher.pattern_count; p += 1 {
		for w := p; w < matcher.word_count; w += 1 {
			score := &matcher.scores[p + 1][w + 1]
			pre_miss := &matcher.scores[p + 1][w]

			match_miss_score := pre_miss[match].score
			miss_miss_score := pre_miss[miss].score

			if p < matcher.pattern_count - 1 {
				match_miss_score -= fuzzy_skip_penalty(matcher, w)
				miss_miss_score -= fuzzy_skip_penalty(matcher, w)
			}

			if match_miss_score > miss_miss_score {
				s: FuzzyScoreInfo
				s.score = match_miss_score
				s.prev = match
				score[miss] = s
			} else {
				s: FuzzyScoreInfo
				s.score = miss_miss_score
				s.prev = miss
				score[miss] = s
			}

			pre_match := &matcher.scores[p][w]

			match_match_score :=
				fuzzy_allow_match(matcher, p, w, match) ? cast(int)pre_match[match].score + fuzzy_match_bonus(matcher, p, w, match) : awful_score

			miss_match_score :=
				fuzzy_allow_match(matcher, p, w, miss) ? cast(int)pre_match[miss].score + fuzzy_match_bonus(matcher, p, w, miss) : awful_score

			if match_match_score > miss_match_score {
				s: FuzzyScoreInfo
				s.score = match_match_score
				s.prev = match
				score[match] = s
			} else {
				s: FuzzyScoreInfo
				s.score = miss_match_score
				s.prev = miss
				score[match] = s
			}
		}
	}
}

fuzzy_match_bonus :: proc(matcher: ^FuzzyMatcher, p: int, w: int, last: int) -> int {
	assert(matcher.lower_pattern[p] == matcher.lower_word[w])

	s := 1

	is_pattern_single_case := (cast(uint)matcher.pattern_type_set == 1 << cast(uint)FuzzyCharType.Lower)
	is_pattern_single_case |= (cast(uint)matcher.pattern_type_set == 1 << cast(uint)FuzzyCharType.Upper)

	// Bonus: case matches, or a Head in the pattern aligns with one in the word.
	// Single-case patterns lack segmentation signals and we assume any character
	// can be a head of a segment.
	if matcher.pattern[p] == matcher.word[w] ||
	   (matcher.word_role[w] == FuzzyCharRole.Head &&
			   (is_pattern_single_case || matcher.pattern_role[p] == FuzzyCharRole.Head)) {
		s += 1
		//fmt.println("match 1");
	}

	// Bonus: a consecutive match. First character match also gets a bonus to
	// ensure prefix final match score normalizes to 1.0.
	if w == 0 || last == match {
		s += 2
		//fmt.println("match 2");
	}

	// Penalty: matching inside a segment (and previous char wasn't matched).
	if matcher.word_role[w] == FuzzyCharRole.Tail && p > 0 && last == miss {
		s -= 3
		//fmt.println("match 3");
	}

	// Penalty: a Head in the pattern matches in the middle of a word segment.
	if matcher.pattern_role[p] == FuzzyCharRole.Head && matcher.word_role[w] == FuzzyCharRole.Tail {
		s -= 1
		//fmt.println("match 4");
	}

	// Penalty: matching the first pattern character in the middle of a segment.
	if p == 0 && matcher.word_role[w] == FuzzyCharRole.Tail {
		s -= 4
		//fmt.println("match 5");
	}

	assert(s <= perfect_bonus)

	return s
}

fuzzy_allow_match :: proc(matcher: ^FuzzyMatcher, p: int, w: int, last: int) -> bool {
	if matcher.lower_pattern[p] != matcher.lower_word[w] {
		return false
	}

	if last == miss {

		if matcher.word_role[w] == FuzzyCharRole.Tail &&
		   (matcher.word[w] == matcher.lower_word[w] ||
				   0 >= (cast(uint)matcher.word_type_set & 1 << cast(uint)FuzzyCharType.Lower)) {
			return false
		}
	}

	return true
}
