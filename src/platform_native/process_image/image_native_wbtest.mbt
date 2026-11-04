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
