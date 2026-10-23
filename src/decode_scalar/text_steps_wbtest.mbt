///|
fn finish_text(
  cursor : Utf8Admission,
) -> Result[Int64, Utf8AdmissionIssue] raise {
  for _ in 0..<10000 {
    let before = cursor.offset
    match cursor.advance() {
      Utf8AdmissionContinue => assert_true(cursor.offset - before <= 128)
      Utf8AdmissionComplete(bytes) => return Ok(bytes)
      Utf8AdmissionFailed(issue) => return Err(issue)
      Utf8AdmissionTerminal => abort("premature Text terminal")
    }
  }
  abort("Text measurement did not terminate")
}

///|
test "resumed UTF-8 measurement preserves exact boundaries and Unicode errors" {
  for
    (text, bytes) in [
      (String::make(129, 'a'), 129L),
      (String::make(129, 'é'), 258L),
      (String::make(129, '😀'), 516L),
    ] {
    let exact = start_utf8_admission(text, bytes).unwrap()
    assert_eq(finish_text(exact), Ok(bytes))
    assert_true(exact.text is None)
    assert_true(exact.advance() is Utf8AdmissionTerminal)
    let short = start_utf8_admission(text, bytes - 1L)
    match short {
      Err(issue) => assert_eq(issue, LimitExceeded)
      Ok(cursor) => assert_eq(finish_text(cursor), Err(LimitExceeded))
    }
    assert_eq(admit_utf8_length64(text, bytes), Ok(bytes))
  }
  let invalid = String::make(129, 'a') +
    String::from_array([(0xd800).unsafe_to_char()])
  for limit in [-1L, 0L, 129L, 130L, 1000L] {
    let resumed = match start_utf8_admission(invalid, limit) {
      Err(issue) => Err(issue)
      Ok(cursor) => finish_text(cursor)
    }
    assert_eq(resumed, admit_utf8_length64(invalid, limit))
  }
}

///|
test "resumed UTF-8 cancellation drops only its borrowed Text" {
  let text = String::make(129, 'é')
  let cursor = start_utf8_admission(text, 258L).unwrap()
  assert_true(cursor.advance() is Utf8AdmissionContinue)
  assert_eq(cursor.offset, 64)
  assert_eq(cursor.bytes, 128L)
  cursor.cancel()
  cursor.cancel()
  assert_true(cursor.advance() is Utf8AdmissionTerminal)
  assert_eq(text.length(), 129)
}

///|
test "resumed UTF-8 ASCII preserves scalar quantum and mixed error precedence" {
  for prefix in [63, 64, 65] {
    let text = String::make(prefix, 'a') + "😀z"
    let bytes = prefix.to_int64() + 5L
    let cursor = start_utf8_admission(text, bytes).unwrap()
    assert_true(cursor.advance() is Utf8AdmissionContinue)
    assert_eq(cursor.offset, if prefix == 63 { 65 } else { 64 })
    assert_eq(cursor.bytes, if prefix == 63 { 67L } else { 64L })
    assert_eq(finish_text(cursor), Ok(bytes))
    let malformed = String::make(prefix, 'a') +
      String::from_array([(0xd800).unsafe_to_char()])
    for limit in [prefix.to_int64(), prefix.to_int64() + 1L, 1000L] {
      let actual = match start_utf8_admission(malformed, limit) {
        Err(issue) => Err(issue)
        Ok(value) => finish_text(value)
      }
      assert_eq(actual, admit_utf8_length64(malformed, limit))
    }
  }
  let overflow = start_utf8_admission("éa", 2L).unwrap()
  assert_true(overflow.advance() is Utf8AdmissionFailed(LimitExceeded))
  assert_eq(overflow.offset, 1)
  assert_eq(overflow.bytes, 2L)
  assert_true(overflow.text is None)
  assert_true(overflow.advance() is Utf8AdmissionTerminal)
}
