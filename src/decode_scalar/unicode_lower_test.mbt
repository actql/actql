///|
test "pinned full lowercase is scalar based and distinct from case folding" {
  for
    (input, expected) in [
      ('A', "a"),
      ('I', "i"),
      ('İ', "i\u{0307}"),
      ('ǲ', "ǳ"),
      ('Σ', "σ"),
      ('ẞ', "ß"),
      ('Ꭰ', "ꭰ"),
      ('𐐀', "𐐨"),
      ('𐵐', "𐵰"),
      ('Ᲊ', "ᲊ"),
    ] {
    assert_eq(@decode_scalar.unicode_lower_mapping(input), Some(expected))
  }
  for
    input in [
      'ß', 'ﬃ', 'σ', 'ς', 'ꭰ', 'ͅ', 'ʰ', '🄰', '́', '日', '😀', '\r',
      '\n',
    ] {
    assert_eq(@decode_scalar.unicode_lower_mapping(input), None)
  }
}

///|
test "pinned context properties retain Cased and Case_Ignorable overlap" {
  for
    input in [
      'A', 'z', 'Σ', 'ς', 'ǲ', 'Ꭰ', 'ꭰ', 'Ᲊ', 'ᲊ', '𐵐', '𐵰', '🄰',
    ] {
    assert_true(@decode_scalar.unicode_is_cased(input))
    assert_false(@decode_scalar.unicode_is_case_ignorable(input))
  }
  for input in ['ͅ', 'ʰ'] {
    assert_true(@decode_scalar.unicode_is_cased(input))
    assert_true(@decode_scalar.unicode_is_case_ignorable(input))
    assert_eq(@decode_scalar.unicode_lower_mapping(input), None)
  }
  for input in ['\'', '’', '́', 'ʼ', '\u{200d}', '\u{fe0f}', '\u{e0100}'] {
    assert_false(@decode_scalar.unicode_is_cased(input))
    assert_true(@decode_scalar.unicode_is_case_ignorable(input))
  }
  for input in [' ', '-', '日', '😀', '\r', '\n', '\u{10ffff}'] {
    assert_false(@decode_scalar.unicode_is_cased(input))
    assert_false(@decode_scalar.unicode_is_case_ignorable(input))
  }
}

///|
test "pinned context range lookup includes endpoints and excludes gaps" {
  for input in ['A', 'Z', 'a', 'z', '\u{1f130}', '\u{1f149}'] {
    assert_true(@decode_scalar.unicode_is_cased(input))
  }
  for input in ['@', '[', '`', '{', '\u{1f12f}', '\u{1f14a}'] {
    assert_false(@decode_scalar.unicode_is_cased(input))
  }
  for input in ['\u{e0100}', '\u{e01ef}'] {
    assert_true(@decode_scalar.unicode_is_case_ignorable(input))
  }
  for input in ['\u{e00ff}', '\u{e01f0}'] {
    assert_false(@decode_scalar.unicode_is_case_ignorable(input))
  }
}
