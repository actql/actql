///|
test "original Reader open kind is independent of diagnostic detail" {
  for detail in ["", "filesystem diagnostic detail omitted", "generation mismatch", "other failure"] {
    assert_true(reader_open_issue(reader_open_kind(2), detail) is GenerationMismatch)
    assert_true(reader_open_issue(reader_open_kind(1), detail) is Read(actual) && actual == detail)
  }
}

///|
test "missing Reader kind cannot imply success or generation mismatch" {
  assert_true(reader_open_issue(reader_open_kind(0), "generation mismatch") is Read(_))
  assert_true(reader_open_issue(reader_open_kind(-1), "") is Read(_))
}
