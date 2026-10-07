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
