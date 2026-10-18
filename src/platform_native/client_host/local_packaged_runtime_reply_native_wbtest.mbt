///|
test "runtime transport refuses missing original supply before path capture" {
  let reply = capture_native_local_packaged_runtime_reply(
    None,
    "/a-runtime-that-must-not-be-opened",
    "a".repeat(40),
    "darwin-arm64",
    "b".repeat(64),
    65536,
  )
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 6)
  assert_true(reply.original_host() is None)
  assert_true(reply.original_read() is None)
  assert_true(reply.original_runtime() is None)
}

///|
test "Runtime Host pair entrance refuses missing originals without direct-read fallback" {
  let reply = capture_native_local_packaged_runtime_in_host_resources_reply(
    None,
    "/this-root-must-not-be-acquired",
    "a".repeat(40),
    "darwin-arm64",
    "b".repeat(64),
    65536,
  )
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 6)
  assert_true(reply.original_host() is None)
  assert_true(reply.original_read() is None)
  assert_true(reply.original_runtime() is None)
}

///|
test "runtime transport does not adopt a legacy projection for scoped cleanup" {
  let legacy = local_runtime_empty(None)
  let current = current_native_local_packaged_runtime_reply(legacy)
  assert_eq(current.operation_tag(), 2)
  assert_eq(current.issue_family(), 6)
  assert_true(
    current.original_runtime() is Some(value) && physical_equal(value, legacy),
  )
  let refused = close_native_local_packaged_runtime_reply(legacy)
  assert_eq(refused.operation_tag(), 3)
  assert_eq(refused.issue_family(), 6)
  assert_false(legacy.closed)
  assert_true(legacy.original_read is None)
  // Its unchanged original legacy Owner can clean up this empty projection;
  // a scoped transport refusal neither performs nor poisons that operation.
  legacy.close().unwrap()
  assert_true(legacy.closed)
}

///|
test "runtime transport preserves imported Unknown apart from pending cleanup" {
  // Immutable failure projection only, not a claimed physical acquisition.
  let unknown : NativeLocalPackagedRuntimeReply = {
    operation: ObservePackagedRuntime,
    original_read: None,
    runtime: None,
    issue: Some(OriginalRead(@arena.Child(@resources.Unknown))),
  }
  assert_eq(unknown.issue_family(), 7)
  assert_eq(
    {
      ..unknown,
      issue: Some(OriginalRead(@arena.Child(@resources.Unavailable))),
    }.issue_family(),
    8,
  )
  assert_eq({ ..unknown, issue: Some(CleanupPending), }.issue_family(), 9)
  assert_eq(
    {
      ..unknown,
      issue: Some(
        OriginalHostResources(@arena.Read(@arena.Child(@resources.Unknown))),
      ),
    }.issue_family(),
    7,
  )
  assert_eq(
    {
      ..unknown,
      issue: Some(
        OriginalHostResources(@arena.Read(@arena.Child(@resources.Unavailable))),
      ),
    }.issue_family(),
    10,
  )
}

///|
test "runtime transport retains the exact pending runtime and original failure" {
  let pending = local_runtime_empty(None)
  let issue : NativeLocalPackagedRuntimeIssue = Physical(
    @filesystem.Read("retained original failure"),
  )
  let reply = local_packaged_runtime_unit_reply(
    ClosePackagedRuntime,
    pending,
    Err(issue),
  )
  assert_eq(reply.issue_family(), 5)
  assert_true(reply.issue is Some(Physical(Read("retained original failure"))))
  assert_true(
    reply.original_runtime() is Some(value) && physical_equal(value, pending),
  )
  assert_false(pending.closed)
  pending.close().unwrap()
}
