///|
test "native process image identity is bounded and stable" {
  let first = current_executable_cid(268435456L, 65536).unwrap()
  let second = current_executable_cid(268435456L, 4096).unwrap()
  assert_eq(first, second)
  let holder_chunk = current_executable_cid(268435456L, 1048576).unwrap()
  assert_eq(first, holder_chunk)
  assert_true(first.has_prefix("sha256:"))
  assert_eq(first.length(), 71)
  assert_true(current_executable_cid(1L, 1) is Err(CapacityExceeded))
  assert_true(current_executable_cid(0L, 1) is Err(InvalidLimit))
  assert_true(current_executable_cid(268435456L, 1048577) is Err(InvalidLimit))
}

///|
test "native process image reader predicates preserve ready and EOF states" {
  let reader = open_reader_ffi(268435456L)
  assert_true(reader_ready_ffi(reader))
  assert_false(reader_eof_ffi(reader))
  assert_eq(reader_next_ffi(reader, 1), 0)
  assert_eq(reader_chunk_ffi(reader).length(), 1)
  assert_false(reader_eof_ffi(reader))
  while !reader_eof_ffi(reader) {
    assert_eq(reader_next_ffi(reader, 1048576), 0)
  }
  assert_true(reader_eof_ffi(reader))
  assert_eq(reader_close_ffi(reader), 0)
  assert_false(reader_ready_ffi(reader))
}
