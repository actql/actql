///|
fn replay_journal_test_environment(
  library : @sqlite.Library,
  path : String,
) -> ControlEnvironment {
  {
    sqlite_library: library, journal_path: path, max_record_bytes: 262144L,
    site_key: "cleanup-test-site", site_generation: 4,
    runtime_bundle_cid: cleanup_test_cid("a".repeat(64)),
    max_operations: 4, max_transfers: 4, max_bytes: 1048576L,
  }
}

///|
test "replay retains one original Journal and refuses a replacement opener" {
  let (library, original, request, path, _) = cleanup_test_open("replay-original-handle")
  original.accept(request).unwrap() |> ignore
  let retained : Ref[ControlReplayJournalCustody?] = Ref(Some(ReplayJournalHandle(original)))
  let foreign = replay_journal_test_environment(library, path + ".replacement")
  assert_true(open_control_replay_journal(foreign, retained) is None)
  assert_true(retained.val is Some(ReplayJournalHandle(value)) && physical_equal(value, original))
  // This adversarial caller entry is not an injected close failure or Cloud
  // ACK. The same real Journal remains readable until actual checked close.
  assert_eq(@remote.dispatch_record_revision(original.require(request).unwrap()), 0)
  assert_true(retry_control_replay_journal_cleanup(retained))
  assert_true(retained.val is None)
  assert_true(retry_control_replay_journal_cleanup(retained))
  let restored = open_control_replay_journal(
    replay_journal_test_environment(library, path), retained,
  ).unwrap()
  assert_eq(@remote.dispatch_record_revision(restored.require(request).unwrap()), 0)
  assert_false(restored.cancellation_requested(request).unwrap())
  assert_true(retry_control_replay_journal_cleanup(retained))
}

///|
test "failed physical replay open keeps original cleanup custody before any replacement" {
  let (library, initial, _, path, _) = cleanup_test_open("replay-open-failure")
  initial.close_checked().unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let retained : Ref[ControlReplayJournalCustody?] = Ref(None)
  assert_true(open_control_replay_journal(
    replay_journal_test_environment(library, root), retained,
  ) is None)
  let original = match retained.val {
    Some(ReplayJournalOpenFailure(value)) => value
    _ => { fail("actual failed opener lost its cleanup carrier"); return }
  }
  assert_true(original.issue() is @journal.Physical(@sqlite.DatabaseOpen(_)))
  assert_true(open_control_replay_journal(
    replay_journal_test_environment(library, path), retained,
  ) is None)
  assert_true(retained.val is Some(ReplayJournalOpenFailure(value)) && physical_equal(value, original))
  assert_true(retry_control_replay_journal_cleanup(retained))
  assert_true(retained.val is None)
  // Handle retirement cannot rewrite the original physical failure diagnostic.
  assert_true(original.issue() is @journal.Physical(@sqlite.DatabaseOpen(_)))
  assert_true(retry_control_replay_journal_cleanup(retained))
}

///|
test "pre-acquisition replay refusal retains no physical custody" {
  let (library, initial, _, path, _) = cleanup_test_open("replay-refusal")
  initial.close_checked().unwrap()
  let retained : Ref[ControlReplayJournalCustody?] = Ref(None)
  let environment = replay_journal_test_environment(library, path)
  let invalid : ControlEnvironment = { ..environment, max_record_bytes: -1L }
  assert_true(open_control_replay_journal(invalid, retained) is None)
  assert_true(retained.val is None)
  assert_true(retry_control_replay_journal_cleanup(retained))
  let restored = open_control_replay_journal(environment, retained).unwrap()
  assert_true(restored.recover_after("").unwrap() is None)
  assert_true(retry_control_replay_journal_cleanup(retained))
}
