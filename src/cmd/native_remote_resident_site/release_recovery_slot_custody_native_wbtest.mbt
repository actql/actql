///|
/// Real descriptor/lock and saved-row controls only, not a prepared installed
/// Resident, whole Run release, Provider operation or physical child stop.
test "release recovery busy Slot closes only its original refused description before returning" {
  let progress_events : Array[(String, Array[(String, String)])] = []
  let observe_progress = (kind, fields) => progress_events.push((kind, fields))
  let (library, journal, request, journal_path, _) = cleanup_test_open(
    "release-busy-slot",
  )
  journal.accept(request).unwrap() |> ignore
  let (root, path) = orphan_store_test_root("release-busy-slot")
  let slot_path = path + "/original.slot"
  let foreign = @slot.open_native_executor_slot(slot_path).unwrap()
  assert_true(foreign.try_acquire().unwrap())
  let matches = recovery_open_test_matches(
    path,
    path + "/must-not-open.sqlite3",
    cleanup_test_cid("a".repeat(64)),
  )
  let opens = Ref(0)
  let environment : ControlEnvironment = {
    ..replay_journal_test_environment(library, journal_path),
    journal_path: path + "/must-not-open.sqlite3",
    crypto_library: _ => {
      opens.val += 1
      Err("busy Slot must not load Crypto")
    },
  }
  let retained : Ref[StoppedReleaseRecovery?] = Ref(None)
  assert_false(
    recover_stopped_release(
      matches,
      environment,
      request,
      retained,
      Ref(0),
      report_progress=observe_progress,
    ),
  )
  assert_true(retained.val is None)
  assert_eq(opens.val, 0)
  assert_eq(root.inspect_generation("must-not-open.sqlite3").unwrap(), None)
  assert_eq(foreign.verify_current_hold(), Ok(()))
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    0,
  )
  assert_false(journal.cancellation_requested(request).unwrap())
  assert_true(foreign.close())
  journal.close_checked().unwrap()
  root.close().unwrap()
  assert_eq(progress_events, [])
}

///|
test "release recovery refuses a locked stale inode and retires that same Slot without touching replacement" {
  let (root, path) = orphan_store_test_root("release-replaced-slot")
  let slot_path = path + "/original.slot"
  let original_slot = @slot.open_native_executor_slot(slot_path).unwrap()
  let generation = root.inspect_generation("original.slot").unwrap().unwrap()
  // Owned fixture fault only: replace the named file while its old description
  // remains open. A production Site never unlinks/recreates its active Slot.
  root.reclaim_generation("original.slot", generation).unwrap()
  let replacement = @slot.open_native_executor_slot(slot_path).unwrap()
  assert_true(replacement.try_acquire().unwrap())
  let original = match
    acquire_release_recovery_slot_with_custody(original_slot, "same-recovery") {
    Err(value) => value
    Ok(_) => {
      fail(
        "stale inode acquired recovery preparation despite named replacement",
      )
      abort("unexpected recovery")
    }
  }
  assert_true(physical_equal(original.slot, original_slot))
  assert_eq(original.failure, "release recovery Slot current hold unconfirmed")
  assert_eq(original.slot.verify_current_hold(), Err(@slot.Replaced))
  assert_true(original.journal.val is None)
  assert_true(original.bundles is None)
  assert_false(original.slot_closed)
  assert_false(original.slot_close_unknown)
  assert_eq(replacement.verify_current_hold(), Ok(()))
  assert_true(retry_release_recovery_open_cleanup(original))
  assert_true(original.slot_closed)
  assert_eq(original.failure, "release recovery Slot current hold unconfirmed")
  assert_false(original.slot_close_unknown)
  assert_true(retry_release_recovery_open_cleanup(original))
  assert_eq(replacement.verify_current_hold(), Ok(()))
  assert_true(replacement.close())
  root.close().unwrap()
}
