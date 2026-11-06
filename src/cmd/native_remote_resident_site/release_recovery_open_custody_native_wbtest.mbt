///|
// These isolated recovery constructor cases supply actual existing nominal
// test Libraries. They do not substitute an installed command entry or claim
// scoped Resident/component qualification. Production uses its own carrier.
fn recovery_open_test_environment(
  matches : @argparse.Matches,
) -> ControlEnvironment raise CommandStop {
  let library = @sqlite.load_library(required(matches, "sqlite-library")).unwrap()
  {
    sqlite_library: library,
    crypto_library: path => {
      @signature.load_library(path).map_err(_ => "fixture Crypto load failed")
    },
    journal_path: required(matches, "journal"),
    max_record_bytes: required_int64(matches, "max-record-bytes"),
    site_key: required(matches, "site-key"),
    site_generation: required_int(matches, "site-generation"),
    runtime_bundle_cid: required(matches, "runtime-bundle-cid"),
    max_operations: required_int(matches, "max-operations"),
    max_transfers: required_int(matches, "max-transfers"),
    max_bytes: required_int64(matches, "max-bytes"),
  }
}

///|
fn recovery_open_test_matches(
  path : String,
  journal_path : String,
  runtime_bundle_cid : String,
) -> @argparse.Matches raise {
  let root = @filesystem.open_root(path).unwrap()
  let pem = @utf8.encode(control_bundle_test_authorities()[0].public_key_pem)
  let writer = root
    .create_writer("issuer-stage", pem.length().to_int64())
    .unwrap()
  writer.append(pem).unwrap()
  writer.seal("issuer.pem").unwrap() |> ignore
  root.close().unwrap()
  command().parse(argv=[
    "--sqlite-library",
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    "--crypto-library",
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    "--journal",
    journal_path,
    "--runtime-root",
    path,
    "--executor-slot",
    path + "/original.slot",
    "--site-key",
    "cleanup-test-site",
    "--site-generation",
    "4",
    "--runtime-bundle-cid",
    runtime_bundle_cid,
    "--bundle-public-key-root",
    path,
    "--bundle-public-key-file",
    "issuer.pem",
    "--bundle-issuer",
    "bundle-authority-a",
    "--bundle-key-id",
    "key-a",
    "--target-triple",
    "aarch64-apple-darwin",
    "run",
  ])
}

///|
test "failed release preparation holds original Bundle Journal and Slot through pending close" {
  let progress_events : Array[(String, Array[(String, String)])] = []
  let observe_progress = (kind, fields) => progress_events.push((kind, fields))
  let (_, seeded, request, journal_path, _) = cleanup_test_open(
    "release-open-partial",
  )
  seeded.accept(request).unwrap() |> ignore
  seeded.close_checked().unwrap()
  let (temporary, path) = control_bundle_test_open(
    "release-open-missing-bundle",
  )
  temporary.close_checked().unwrap()
  let matches = recovery_open_test_matches(
    path,
    journal_path,
    cleanup_test_cid("a".repeat(64)),
  )
  let slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let identity = @remote.dispatch_request_identity(request)
  let original = match
    open_release_recovery_with_custody(
      matches,
      recovery_open_test_environment(matches),
      slot,
      identity,
    ) {
    Err(value) => value
    Ok(_) => {
      fail("missing original Bundle was accepted as prepared recovery")
      return
    }
  }
  assert_eq(original.request_identity, identity)
  assert_eq(original.failure, "release recovery saved Bundle unavailable")
  let bundle = original.bundles.unwrap()
  let journal = match original.journal.val {
    Some(ReplayJournalHandle(same)) => same
    _ => {
      fail("acquired original Journal was lost")
      return
    }
  }
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  // Real installer activity blocks the original Store close; no fake ACK.
  let installer = control_bundle_test_install(bundle, "1")
  assert_false(retry_release_recovery_open_cleanup(original))
  assert_true(original.bundles is Some(same) && physical_equal(same, bundle))
  assert_true(
    original.journal.val is Some(ReplayJournalHandle(same)) &&
    physical_equal(same, journal),
  )
  assert_eq(slot.verify_current_hold(), Ok(()))
  assert_false(original.slot_closed)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_false(retry_release_recovery_open_cleanup(original))
  installer.cancel().unwrap()
  assert_true(retry_release_recovery_open_cleanup(original))
  assert_true(original.bundles is None)
  assert_true(original.journal.val is None)
  assert_true(original.slot_closed)
  assert_eq(original.failure, "release recovery saved Bundle unavailable")
  assert_true(retry_release_recovery_open_cleanup(original))
  let current = fresh_journal(
    replay_journal_test_environment(
      @sqlite.load_library(
        @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
      ).unwrap(),
      journal_path,
    ),
  ).unwrap()
  assert_eq(
    @remote.dispatch_record_revision(current.require(request).unwrap()),
    revision,
  )
  assert_eq(
    @remote.dispatch_record_state_codes(current.require(request).unwrap())[0],
    0,
  )
  current.close_checked().unwrap()
  // The real controller caller must return pending after failed preparation,
  // not throw out of the controller and discard its other responsibilities.
  let retained : Ref[StoppedReleaseRecovery?] = Ref(None)
  assert_false(
    recover_stopped_release(
      matches,
      recovery_open_test_environment(matches),
      request,
      retained,
      Ref(0),
      report_progress=observe_progress,
    ),
  )
  assert_true(retained.val is None)
  let next = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(next.try_acquire().unwrap())
  assert_true(next.close())
  assert_eq(progress_events, [
    (
      "release-recovery-preparation-failed",
      [("request_cid", @remote.dispatch_request_identity(request))],
    ),
  ])
}

///|
test "release preparation retains failed Journal construction without opening Bundle" {
  let (unused, path) = control_bundle_test_open("release-open-failed-journal")
  unused.close_checked().unwrap()
  let root = @filesystem.open_root(path).unwrap()
  root.create_directory("journal-is-directory").unwrap() |> ignore
  root.close().unwrap()
  let matches = recovery_open_test_matches(
    path,
    path + "/journal-is-directory",
    cleanup_test_cid("a".repeat(64)),
  )
  let slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = match
    open_release_recovery_with_custody(
      matches,
      recovery_open_test_environment(matches),
      slot,
      "original-recovery",
    ) {
    Err(value) => value
    Ok(_) => {
      fail("failed Journal construction was accepted")
      return
    }
  }
  assert_eq(original.failure, "release recovery journal unavailable")
  assert_true(original.bundles is None)
  let failure = match original.journal.val {
    Some(ReplayJournalOpenFailure(same)) => same
    _ => {
      fail("failed original Journal custody was lost")
      return
    }
  }
  assert_true(failure.issue() is @journal.Physical(@sqlite.DatabaseOpen(_)))
  assert_eq(slot.verify_current_hold(), Ok(()))
  assert_true(retry_release_recovery_open_cleanup(original))
  assert_true(original.journal.val is None)
  assert_true(original.slot_closed)
  assert_true(failure.issue() is @journal.Physical(@sqlite.DatabaseOpen(_)))
  assert_true(retry_release_recovery_open_cleanup(original))
}

///|
test "successful release preparation transfers original handles without cleanup or execution" {
  let (installed, path) = control_bundle_test_open("release-open-prepared")
  let installer = control_bundle_test_install(installed, "1")
  installer.append(b"runtime-one").unwrap()
  installer.seal().unwrap() |> ignore
  installed.activate(control_bundle_test_cid("1")).unwrap() |> ignore
  installed.close_checked().unwrap()
  let matches = recovery_open_test_matches(
    path,
    path + "/dispatch.sqlite3",
    control_bundle_test_cid("1"),
  )
  let slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let owner = open_release_recovery_with_custody(
    matches,
    recovery_open_test_environment(matches),
    slot,
    "original-recovery",
  ).unwrap()
  assert_true(physical_equal(owner.slot, slot))
  assert_eq(owner.request_identity, "original-recovery")
  assert_false(owner.bundle_closed)
  assert_true(owner.terminal_close is RecoveryTerminalOpen)
  assert_eq(slot.verify_current_hold(), Ok(()))
  assert_true(owner.journal.recover_after("").unwrap() is None)
  assert_eq(owner.bundles.capacity_usage().unwrap().reserved_bytes, 11L)
  // Fixture teardown is physical handle retirement, not a formal Run release.
  owner.bundles.close_checked().unwrap()
  owner.journal.close_checked().unwrap()
  assert_true(slot.close())
}
