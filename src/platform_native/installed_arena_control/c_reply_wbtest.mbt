///|
// Source-prepared C reply boundaries. The metadata fixture does not acquire
// mapping/VM/worker resources or select a numerical product profile.
fn prepared_reply(retained_bytes : Int64) -> InstalledArenaReply {
  prepare_installed_arena_reply(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    1024L,
    0,
    1,
    0,
    0L,
    retained_bytes,
    1024L,
    65536L,
  )
}

///|
test "prepare reply cannot be mistaken for original acquired availability" {
  let intent = prepared_reply(0L)
  assert_eq(intent.operation_tag(), 1)
  assert_eq(intent.issue_family(), 0)
  guard intent.original_host() is Some(original) else {
    abort("prepared original is missing")
  }
  let current = current_installed_arena_reply(original)
  assert_eq(current.operation_tag(), 3)
  assert_eq(current.issue_family(), 1)
  guard current.original_host() is Some(same) else {
    abort("original custody is missing")
  }
  assert_true(physical_equal(original, same))
  let closed = close_installed_arena_reply(original)
  assert_eq(closed.operation_tag(), 4)
  assert_eq(closed.issue_family(), 0)
}

///|
test "constructor refusal has no fabricated Host or successful issue family" {
  let rejected = prepared_reply(1L)
  assert_eq(rejected.operation_tag(), 1)
  assert_eq(rejected.issue_family(), 1)
  assert_true(rejected.original_host() is None)
  assert_eq(rejected.issue, Some(@bootstrap.Unavailable))
}

///|
test "physical zero payload remains the original typed failure" {
  let intent = prepared_reply(0L)
  guard intent.original_host() is Some(original) else {
    abort("prepared original is missing")
  }
  let failed = original_unit_reply(Close, original, Err(@bootstrap.Physical(0)))
  assert_eq(failed.issue_family(), 6)
  assert_eq(failed.issue, Some(@bootstrap.Physical(0)))
  assert_eq(close_installed_arena_reply(original).issue_family(), 0)
}

///|
test "Resource failure remains distinct and retains the original Host" {
  let intent = prepared_reply(0L)
  guard intent.original_host() is Some(original) else {
    abort("prepared original is missing")
  }
  let failed = original_unit_reply(
    Acquire,
    original,
    Err(@bootstrap.Resource(@resources.ExecutionLimit)),
  )
  assert_eq(failed.operation_tag(), 2)
  assert_eq(failed.issue_family(), 7)
  assert_eq(failed.issue, Some(@bootstrap.Resource(@resources.ExecutionLimit)))
  guard failed.original_host() is Some(same) else {
    abort("failed operation lost its original Host")
  }
  assert_true(physical_equal(original, same))
  assert_eq(close_installed_arena_reply(original).issue_family(), 0)
}
