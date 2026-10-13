///|
test "Content MIME case projection preserves the original report and exact parameter values" {
  for
    (reported, expected) in [
      ("Application/PDF", "application/pdf"),
      ("TEXT/HTML;Charset=UTF-8", "text/html;charset=UTF-8"),
      (
        "Multipart/Form-Data; Boundary=AbC123", "multipart/form-data; boundary=AbC123",
      ),
      (
        "Application/JSON; Profile=\"A/B;X=Upper\"", "application/json; profile=\"A/B;X=Upper\"",
      ),
      ("Text/Plain;Label=\"e\u{301}🚀\"", "text/plain;label=\"e\u{301}🚀\""),
      ("Text/Plain;Label=\"é🚀\"", "text/plain;label=\"é🚀\""),
      ("Text/Plain;Q=\"A\\\";B\";X=Z", "text/plain;q=\"A\\\";B\";x=Z"),
      ("Text/Plain;; X=One;x=Two ", "text/plain;; x=One;x=Two "),
    ] {
    assert_eq(normalize_content_media_type_case(reported, 1024), Ok(expected))
    assert_eq(normalize_content_media_type_case(expected, 1024), Ok(expected))
  }
  assert_true(
    normalize_content_media_type_case("Text/Plain;Label=\"e\u{301}\"", 1024) !=
    normalize_content_media_type_case("Text/Plain;Label=\"é\"", 1024),
  )
}

///|
test "Content MIME projection refuses incomplete syntax without repair or MIME defaults" {
  for
    reported in [
      "", "PDF", "/pdf", "application/", "application//pdf", "app lication/pdf",
      "application/pdf, text/plain", "text/plain;Name", "text/plain;=value", "text/plain;Name=",
      "text/plain;Name =Value", "text/plain;Name=\"open", "text/plain;Name=\"closed\"tail",
      "text/plain;Name=\"line\nfeed\"", "text/plain;Name=\"\\\n\"", "text/plain;Name=non ascii",
      "text/plain\u{0}",
    ] {
    assert_eq(
      normalize_content_media_type_case(reported, 1024),
      Err(InvalidSyntax),
    )
  }
}

///|
test "Content MIME projection admits exact UTF8 limit and refuses one byte short or malformed UTF16" {
  assert_eq(
    normalize_content_media_type_case("Text/Plain", 10),
    Ok("text/plain"),
  )
  assert_eq(
    normalize_content_media_type_case("Text/Plain", 9),
    Err(Utf8(@scalar.LimitExceeded)),
  )
  assert_eq(
    normalize_content_media_type_case("Text/Plain", -1),
    Err(Utf8(@scalar.InvalidLimit)),
  )
  let reported = "Text/Plain;X=\"" +
    String::from_array([(0xd800).unsafe_to_char()]) +
    "\""
  assert_true(
    normalize_content_media_type_case(reported, 1024)
    is Err(Utf8(@scalar.MalformedUtf16(_))),
  )
}
