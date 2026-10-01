///|
test "NFC composition, decomposition, ordering and exclusions" {
  let vectors = [
    ("", ""),
    ("plain ASCII", "plain ASCII"),
    ("e\u{0301}", "é"),
    ("\u{212B}", "Å"),
    ("\u{0344}", "\u{0308}\u{0301}"),
    ("A\u{0315}\u{0300}", "À\u{0315}"),
    ("\u{0315}\u{0300}", "\u{0300}\u{0315}"),
    ("A\u{0305}\u{0301}", "A\u{0305}\u{0301}"),
    ("\u{1100}\u{1161}\u{11A8}", "각"),
    ("가\u{11A8}", "각"),
    // The trailing character is itself NFC, but its decomposition can
    // compose with the preceding character.
    ("\u{16D63}\u{16D68}", "\u{16D6A}"),
    // NFC does not perform compatibility decomposition or case folding.
    ("\u{FB01}", "\u{FB01}"),
    ("Straße", "Straße"),
  ]
  for (input, expected) in vectors {
    assert_eq(normalize_nfc(input), Ok(expected))
    assert_eq(normalize_nfc(expected), Ok(expected))
  }
}

///|
test "NFC preserves newlines while document normalization folds CR and CRLF" {
  let vectors = [
    ("\r", "\r", "\n"),
    ("\r\n", "\r\n", "\n"),
    ("\r\r\n\n", "\r\r\n\n", "\n\n\n"),
    ("e\u{0301}\r\n\r각", "é\r\n\r각", "é\n\n각"),
    ("a\rb\r\nc\nd", "a\rb\r\nc\nd", "a\nb\nc\nd"),
    (
      "\u{85}\u{2028}\u{2029}\t", "\u{85}\u{2028}\u{2029}\t", "\u{85}\u{2028}\u{2029}\t",
    ),
    // Newlines remain composition boundaries.
    ("e\r\u{0301}", "e\r\u{0301}", "e\n\u{0301}"),
  ]
  for (input, nfc, document) in vectors {
    assert_eq(normalize_nfc(input), Ok(nfc))
    assert_eq(normalize_nfc_lf(input), Ok(document))
    assert_eq(normalize_nfc_lf(document), Ok(document))
  }
}

///|
fn raw_utf16(units : Array[Int]) -> String {
  String::from_array(units.map(fn(unit) { unit.unsafe_to_char() }))
}

///|
test "normalization rejects unpaired surrogates at original UTF-16 offsets" {
  let vectors = [
    ([0xD800], 0),
    ([0xDBFF], 0),
    ([0xDC00], 0),
    ([0xDFFF], 0),
    ([0xD800, 0x41], 0),
    ([0x41, 0xD800], 1),
    ([0x41, 0xDC00], 1),
    ([0xD800, 0xD800], 0),
    ([0xDC00, 0xD800], 0),
    ([0xDBFF, 0xE000], 0),
    ([0xD800, 0xD7FF], 0),
    ([0x41, 0xD83D, 0xDE00, 0xDC00], 3),
    ([0x41, 0xD83D, 0xDE00, 0xD800], 3),
    // Error offsets refer to the input before composition or newline folding.
    ([0x65, 0x0301, 0x0D, 0x0A, 0xD800], 4),
  ]
  for (units, offset) in vectors {
    let input = raw_utf16(units)
    assert_eq(normalize_nfc(input), Err(UnpairedSurrogate(offset)))
    assert_eq(normalize_nfc_lf(input), Err(UnpairedSurrogate(offset)))
  }
}

///|
test "normalization accepts paired surrogates and scalar boundary values" {
  let input = raw_utf16([
    0xD7FF, 0xD800, 0xDC00, 0xDBFF, 0xDFFF, 0xE000, 0xD83D, 0xDE00,
  ])
  let expected = "\u{D7FF}\u{10000}\u{10FFFF}\u{E000}😀"
  assert_eq(normalize_nfc(input), Ok(expected))
  assert_eq(normalize_nfc_lf(input), Ok(expected))
  // Scalar validity does not require assignment in the pinned UCD.
  assert_eq(normalize_nfc("\u{0378}\u{FFFF}"), Ok("\u{0378}\u{FFFF}"))
}

///|
test "raw UTF-16 comparison preserves equality, prefixes and code-unit order" {
  let ordered = [
    "", "\u{0}", "\n", "\r", "A", "a", "aa", "e\u{0301}", "é", "\u{D7FF}", "\u{10000}",
    "😀", "\u{10FFFF}", "\u{E000}", "\u{FFFF}",
  ]
  for i = 0; i < ordered.length(); i = i + 1 {
    for j = 0; j < ordered.length(); j = j + 1 {
      let expected = if i < j { -1 } else if i == j { 0 } else { 1 }
      assert_eq(compare_utf16(ordered[i], ordered[j]), expected)
    }
  }
}

///|
test "semantic comparison normalizes at the caller boundary" {
  assert_eq(compare_utf16("e\u{0301}", "é"), -1)
  let left = normalize_nfc("e\u{0301}").unwrap()
  let right = normalize_nfc("é").unwrap()
  assert_eq(compare_utf16(left, right), 0)
  // This primitive does not admit text: raw surrogate units can be compared.
  assert_eq(compare_utf16(raw_utf16([0xD800]), raw_utf16([0xDC00])), -1)
  assert_eq(compare_utf16("\r", "\n"), 1)
}

///|
test "long reverse-class runs normalize without crossing starters" {
  // Each run is 64 KiB in UTF-8: n marks of CCC 232 followed by n of CCC 230.
  let n = 16384
  let input_run = String::from_array(
    Array::make(n, '\u{0315}') + Array::make(n, '\u{0300}'),
  )
  let ordered_run = String::from_array(
    Array::make(n, '\u{0300}') + Array::make(n, '\u{0315}'),
  )
  // Leading nonstarters and a second run after a non-composing starter.
  let input = input_run + "!" + input_run
  let expected = ordered_run + "!" + ordered_run
  assert_eq(normalize_nfc(input), Ok(expected))
  assert_eq(normalize_nfc_lf(input), Ok(expected))
  assert_eq(normalize_nfc(expected), Ok(expected))
}

///|
test "long reordered runs preserve equal-class order and composition blocking" {
  let n = 4096
  let equal_class : Array[Char] = []
  for index = 0; index < n; index = index + 1 {
    equal_class.push('\u{0305}')
    equal_class.push('\u{0301}')
  }
  // Both overline and acute are CCC 230; overline must remain before acute,
  // preventing acute from composing with A after CCC 232 marks move right.
  let high = String::from_array(Array::make(n, '\u{0315}'))
  let stable = String::from_array(equal_class)
  let input = "A" + high + stable
  let expected = "A" + stable + high
  assert_eq(normalize_nfc(input), Ok(expected))
  assert_eq(normalize_nfc_lf(input), Ok(expected))
}

///|
test "scalar value admission preserves normalization forms and every newline sequence" {
  for
    value in ["\r", "\n", "\r\n", "é", "e\u{0301}", "\\n", "😀", "\u{0344}"] {
    assert_eq(validate_scalar_text(value), Ok(()))
  }
  for (units, offset) in [([0xD800], 0), ([65, 0xDC00], 1), ([0xD800, 65], 0)] {
    assert_eq(
      validate_scalar_text(
        String::from_array(units.map(n => n.unsafe_to_char())),
      ),
      Err(UnpairedSurrogate(offset)),
    )
  }
  // Identifier normalization remains its separate, unchanged operation.
  assert_eq(normalize_nfc_lf("e\u{0301}\r\n"), Ok("é\n"))
}
