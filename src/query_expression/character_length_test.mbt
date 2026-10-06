///|
test "GoogleSQL character length spellings share the existing len expression" {
  for name in ["LENGTH", "CHAR_LENGTH", "CHARACTER_LENGTH", "char_length"] {
    assert_eq(emit(name + "(x)"), "{\"len\":{\"field\":\"x\"}}")
    assert_eq(emit(name + "(NULL)"), "{\"len\":{\"literal\":null}}")
  }
}

///|
test "character length keeps exact arity and the closed function namespace" {
  for text in ["CHAR_LENGTH()", "CHARACTER_LENGTH('a', 'b')"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  for text in ["ACTQL.CHAR_LENGTH('a')", "`CHAR_LENGTH`('a')"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
      msg=text,
    )
  }
}
