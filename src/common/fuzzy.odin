package common


FuzzyMatcher :: struct {
    pattern: string,
};

make_fuzzy_matcher :: proc (pattern: string) -> FuzzyMatcher {
    return FuzzyMatcher {
        pattern = pattern
    };
}

fuzzy_match :: proc (matcher: FuzzyMatcher, match: string) -> f64 {

  //temp just look at the beginning on the character - will need to learn about fuzzy matching first.

  if matcher.pattern[0] == match[0] {
      return 1.0;
  }


  return 0.0;
}
