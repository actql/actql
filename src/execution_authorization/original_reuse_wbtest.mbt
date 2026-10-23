///|
// Test the actual FFI-visible backing, not a separate array copy.
fn original_reuse_test_buffer_view(value : Bytes) -> FixedArray[Byte] = "%identity"

///|
test "wire admission retains exact private bytes without granting a tuple" {
  let wire = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"original\",\"entries\":[]}"
  let account = admit_account_configuration_json(wire).unwrap()
  let caller = @utf8.encode(wire)
  assert_true(account.retains_original_bytes(caller))
  assert_true(!account.retains_original_bytes(caller + b"\n"))
  original_reuse_test_buffer_view(caller)[0] = 0
  assert_true(!account.retains_original_bytes(caller))
  assert_true(account.retains_original_bytes(@utf8.encode(wire)))
  let extent = account.representation_extent()
  assert_eq(extent.original_byte_buffers, 1L)
  assert_eq(extent.original_bytes, wire.length().to_int64())
  assert_true(
    evaluate_account(account, {
      principal: "operator",
      connection: "local",
      resource: "run",
      operation: "read",
    })
    is Deny(_),
  )
}

///|
test "typed admission and equal CID wire spellings do not invent an original" {
  let wire = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"é😀\",\"entries\":[]}"
  let raw = decode_account_configuration_json(wire).unwrap()
  let typed = admit_account_configuration(raw).unwrap()
  assert_true(!typed.retains_original_bytes(@utf8.encode(wire)))
  assert_eq(typed.representation_extent().original_bytes, 0L)
  let first = admit_account_configuration_json(wire).unwrap()
  let other = admit_account_configuration_json(wire + "\n").unwrap()
  assert_eq(first.configuration_cid(), other.configuration_cid())
  assert_true(!first.retains_original_bytes(@utf8.encode(wire + "\n")))
  assert_true(other.retains_original_bytes(@utf8.encode(wire + "\n")))
  assert_eq(
    first.representation_extent().original_bytes,
    @utf8.encode(wire).length().to_int64(),
  )
}
