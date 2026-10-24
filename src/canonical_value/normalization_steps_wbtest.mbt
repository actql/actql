///|
fn normalization_fixture(value : String, fold : Bool) -> String raise {
  let cursor = start_normalization(value, fold)
  let mut complete = false
  for _ in 0..<10000 {
    if advance_normalization(cursor).unwrap() {
      complete = true
      break
    }
  }
  assert_true(complete)
  let out = StringBuilder()
  for i in 0..<normalization_count(cursor) {
    out.write_char(normalization_scalar(cursor, i).unwrap())
  }
  out.to_string()
}

///|
test "bounded Unicode normalization uses pinned compatibility and full default folding" {
  for
    (source, expected) in [
      ("ＡＢＣ", "ABC"),
      ("ﬁ", "fi"),
      ("①", "1"),
      ("e\u{301}", "é"),
      ("Å", "Å"),
      ("😀", "😀"),
      ("가각", "가각"),
      ("\u{1100}\u{1161}\u{11a8}", "각"),
      ("a\u{315}\u{300}", "à\u{315}"),
      ("\r\n", "\r\n"),
    ] {
    assert_eq(normalization_fixture(source, false), expected)
  }
  for
    (source, expected) in [
      ("Straße", "strasse"),
      ("Σςσ", "σσσ"),
      ("İ", "i\u{307}"),
      ("K", "k"),
      ("e\u{301}", "é"),
      ("😀", "😀"),
      ("ﬃ", "ffi"),
      ("Ａ", "ａ"),
      ("가각", "가각"),
    ] {
    assert_eq(normalization_fixture(source, true), expected)
  }
}

///|
test "bounded normalization refuses malformed scalar data without replacement" {
  let invalid = String::from_array([(0xd800).unsafe_to_char()])
  let cursor = start_normalization(invalid, false)
  assert_eq(advance_normalization(cursor), Err(UnpairedSurrogate(0)))
}
