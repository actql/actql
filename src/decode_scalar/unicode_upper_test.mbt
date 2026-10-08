///|
test "pinned full uppercase mapping is scalar based and locale independent" {
  for
    (input, expected) in [
      ('ß', "SS"),
      ('ﬃ', "FFI"),
      ('ǳ', "Ǳ"),
      ('ᾀ', "ἈΙ"),
      ('ΐ', "Ϊ́"),
      ('ͅ', "Ι"),
      ('ǰ', "J̌"),
      ('i', "I"),
      ('ı', "I"),
      ('σ', "Σ"),
      ('ς', "Σ"),
      ('𐐨', "𐐀"),
      ('𐵰', "𐵐"),
      ('ᲊ', "Ᲊ"),
    ] {
    assert_eq(@decode_scalar.unicode_upper_mapping(input), Some(expected))
  }
  for input in ['ẞ', 'İ', 'Σ', '́', '日', '😀', '\r', '\n'] {
    assert_eq(@decode_scalar.unicode_upper_mapping(input), None)
  }
}
