///|
test "product transport refuses legacy Runtime without adopting a current witness" {
  let runtime = local_runtime_empty(None)
  let observed = observe_native_local_packaged_product_reply(
    runtime,
    "/must-not-open",
    "a".repeat(64),
    "b".repeat(64),
    128,
  )
  assert_eq(observed.operation_tag(), 4)
  assert_eq(observed.issue_family(), 6)
  assert_true(observed.original_host() is None)
  assert_true(observed.original_read() is None)
  assert_true(physical_equal(observed.original_runtime(), runtime))
  assert_eq(observed.metadata_units(), -1)
  let read = read_native_local_packaged_product_reply(runtime)
  assert_eq(read.operation_tag(), 5)
  assert_eq(read.issue_family(), 6)
  assert_eq(read.metadata_unit_at(0), -1)
  assert_false(runtime.closed)
  runtime.close().unwrap()
}

///|
test "product metadata transfer preserves exact UTF16 and rejects missing or foreign operation" {
  // Scalar immutable projection only: this is not an adopted physical witness.
  let runtime = local_runtime_empty(None)
  let reply : NativeLocalPackagedProductReply = {
    runtime,
    operation: 5,
    issue: None,
    metadata: Some("Ω😀"),
  }
  assert_eq(reply.metadata_units(), 3)
  assert_eq(reply.metadata_unit_at(0), 0x03A9)
  assert_eq(reply.metadata_unit_at(1), 0xD83D)
  assert_eq(reply.metadata_unit_at(2), 0xDE00)
  assert_eq(reply.metadata_unit_at(-1), -1)
  assert_eq(reply.metadata_unit_at(3), -1)
  assert_eq({ ..reply, metadata: None, }.metadata_units(), -1)
  assert_eq({ ..reply, operation: 4, }.metadata_units(), -1)
  assert_eq({ ..reply, metadata: Some("a".repeat(4097)), }.metadata_units(), -1)
  assert_eq({ ..reply, issue: Some(CleanupPending), }.metadata_units(), -1)
  runtime.close().unwrap()
}

///|
test "product transport retains same Runtime and original typed failure" {
  let runtime = local_runtime_empty(None)
  let reply : NativeLocalPackagedProductReply = {
    runtime,
    operation: 4,
    issue: Some(OriginalRead(@arena.Child(@resources.Unknown))),
    metadata: None,
  }
  assert_eq(reply.issue_family(), 7)
  assert_true(physical_equal(reply.original_runtime(), runtime))
  assert_eq({ ..reply, issue: Some(CleanupPending), }.issue_family(), 9)
  assert_eq(
    { ..reply, issue: Some(Physical(@filesystem.GenerationMismatch)), }.issue_family(),
    5,
  )
  assert_eq(reply.metadata_units(), -1)
  assert_false(runtime.closed)
  runtime.close().unwrap()
}
