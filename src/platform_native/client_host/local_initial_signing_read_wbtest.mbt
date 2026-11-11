///|
test "initial signing cannot turn copied callback metadata into an original Read or cached Allow" {
  let (host, _) = initial_reviewer_fixture("signing-read-no-fabricated-scope")
  let original = host.restore_initial_signing_original().unwrap()
  let material = host.adopted_current_material().unwrap()
  let library = local_journal_test_library()
  let capture = prepare_native_local_journal_capture(
    host.session,
    library,
    host.epoch.crypto,
    100.0,
    8,
    8388608L,
  )
  // Negative-only copied metadata. This fixture has NO original Arena pair;
  // the positive actual Read/SQL case belongs to native_client's real owner.
  capture.opening = JournalAcquired(host)
  capture.read_callback_active = true
  capture.read_facts_valid = true
  capture.read_material = Some(material)
  let scoped = { ..original, original_read: Some((capture, material)), }
  let tuple : @authorization.AccessTuple = {
    principal: "machine-user",
    connection: "cli",
    resource: "run",
    operation: "resolve",
  }
  let actual_allow = host.authorize(tuple).unwrap()
  assert_true(actual_allow is @authorization.Allow(_))
  capture.read_decisions.push((tuple, actual_allow))
  assert_true(scoped.require_current() is Err(OriginalResourceScopePending))
  assert_true(scoped.authorize(tuple) is Err(OriginalResourceScopePending))
  assert_true(
    scoped.selected_configuration("host.json")
    is Err(OriginalResourceScopePending),
  )
  // Refusal of the invented route does not destroy the genuine legacy owner.
  original.require_current().unwrap()
  capture.read_callback_active = false
  capture.read_facts_valid = false
  capture.clear_read_operation_facts()
  host.close().unwrap()
  assert_true(library.close_checked() is Err(Physical(_)))
}

///|
test "initial signing retains the first invalidation and rejects a different equal material identity" {
  let (host, _) = initial_reviewer_fixture("signing-read-retired-material")
  let original = host.restore_initial_signing_original().unwrap()
  let first = host.adopted_current_material().unwrap()
  let second = host.adopted_current_material().unwrap()
  assert_false(physical_equal(first, second))
  let library = local_journal_test_library()
  let capture = prepare_native_local_journal_capture(
    host.session,
    library,
    host.epoch.crypto,
    100.0,
    8,
    8388608L,
  )
  capture.opening = JournalAcquired(host)
  capture.read_callback_active = true
  capture.read_facts_valid = true
  capture.read_material = Some(second)
  let scoped = { ..original, original_read: Some((capture, first)), }
  assert_true(scoped.require_current() is Err(OriginalResourceScopePending))
  capture.read_operation_issue = Some(SourceChanged)
  assert_true(scoped.require_current() is Err(SourceChanged))
  assert_true(scoped.selected_configuration("host.json") is Err(SourceChanged))
  assert_true(scoped.check_callback_current() is Err(SourceChanged))
  capture.read_callback_active = false
  capture.read_facts_valid = false
  capture.clear_read_operation_facts()
  // Cleanup remains with the actual original even after currentness failed.
  host.close().unwrap()
  assert_true(library.close_checked() is Err(Physical(_)))
}
