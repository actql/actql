///|
test "managed row transfer charges exact UTF-8 bytes" {
  guard managed_row_transfer_bytes("{\"t\":\"ASCII\"}", 13) is Ok(ascii) else {
    fail("ASCII transfer measurement")
  }
  guard managed_row_transfer_bytes("{\"t\":\"日本語\"}", 17) is Ok(japanese) else {
    fail("Japanese transfer measurement")
  }
  guard managed_row_transfer_bytes("{\"t\":\"😀\"}", 12) is Ok(supplementary) else {
    fail("supplementary transfer measurement")
  }
  assert_eq(ascii, 13L)
  assert_eq(japanese, 17L)
  assert_eq(supplementary, 12L)
  assert_true(
    managed_row_transfer_bytes("{\"t\":\"日本語\"}", 16)
    is Err(Configuration(InputUnavailable)),
  )
}

///|
test "managed input readiness preserves mixed port positions" {
  // Already accessible ordinary input, supplied input, managed bridge and
  // retained ordinary import keep the original physical input positions.
  let reads : Array[Int?] = [Some(17), None, None, None]
  let pending = Ref(2)
  assert_true(install_local_managed_input_read(reads, pending, 3, 41))
  assert_eq(pending.val, 1)
  assert_eq(reads, [Some(17), None, None, Some(41)])
  assert_true(install_local_managed_input_read(reads, pending, 2, 29))
  assert_eq(pending.val, 0)
  assert_eq(reads, [Some(17), None, Some(29), Some(41)])
}

///|
test "managed input readiness rejects repeated and foreign installation" {
  let reads : Array[Int?] = [None, None]
  let pending = Ref(2)
  assert_false(install_local_managed_input_read(reads, pending, -1, 9))
  assert_false(install_local_managed_input_read(reads, pending, 2, 9))
  assert_eq(pending.val, 2)
  assert_true(install_local_managed_input_read(reads, pending, 0, 7))
  assert_false(install_local_managed_input_read(reads, pending, 0, 99))
  assert_eq(pending.val, 1)
  assert_eq(reads, [Some(7), None])
  assert_true(install_local_managed_input_read(reads, pending, 1, 11))
  assert_eq(pending.val, 0)
  assert_false(install_local_managed_input_read(reads, pending, 1, 99))
  assert_eq(reads, [Some(7), Some(11)])
}

///|
test "managed input readiness admits zero required imports without writes" {
  let empty : Array[Int?] = []
  let supplied : Array[Int?] = [None, None]
  let pending = Ref(0)
  assert_false(install_local_managed_input_read(empty, pending, 0, 7))
  assert_false(install_local_managed_input_read(supplied, pending, 0, 7))
  assert_eq(pending.val, 0)
  assert_eq(supplied, [None, None])
}

///|
test "managed input readiness keeps the last unfinished import blocking" {
  let reads : Array[Int?] = Array::make(4096, None)
  let pending = Ref(4096)
  for index in 0..<4095 {
    assert_true(install_local_managed_input_read(reads, pending, index, index))
    assert_eq(pending.val, 4095 - index)
  }
  // A retry of a finished transfer cannot hide the one remaining import.
  assert_false(install_local_managed_input_read(reads, pending, 0, -1))
  assert_eq(pending.val, 1)
  assert_true(install_local_managed_input_read(reads, pending, 4095, 4095))
  assert_eq(pending.val, 0)
  for index in 0..<4096 {
    assert_eq(reads[index], Some(index))
  }
}
