///|
// An ordinary legacy Library fixture cannot acquire the original Read route.
// These are actual Journal/descriptor refusal tests, not a funded pair positive.
fn preparation_read_refusal_without_pair() -> (@sqlite.Library, @crypto.Library) raise {
  let capture = journal_capture_fixture("preparation-without-original-read")
  assert_eq(capture.open().issue_family(), 0)
  let calls = Ref(0)
  // Counterfeit callback metadata is only a refusal test. It cannot construct
  // an entered Read, and nested entry must not touch a physical original.
  capture.read_callback_active = true
  assert_true(
    capture.with_original_read(fn(_host) { calls.val += 1 })
    is Err(OriginalResourceScopePending),
  )
  assert_eq(calls.val, 0)
  capture.read_callback_active = false
  assert_true(
    read_binding_in_original_read(capture, fn(_host, _operations) {
      calls.val += 1
      Ok(())
    })
    is Err(OriginalRead(None, OriginalResourceScopePending)),
  )
  assert_eq(calls.val, 0)
  assert_true(
    capture.with_original_read(fn(_host) {
      calls.val += 1
      "must not run"
    })
    is Err(InvalidInput),
  )
  assert_eq(calls.val, 0)
  assert_true(
    capture.submission_originals_in_original_read()
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.check_current_in_original_read()
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.selected_configuration_in_original_read("config.json")
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.configuration_in_original_read()
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.lookup_submitted_run_original_by_id_in_original_read(
      "principal", "connection", "selector-only",
    )
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.lookup_submitted_run_state_by_id_in_original_read(
      "principal", "connection", "selector-only", 0.0,
    )
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.authority_scope_cid_in_original_read("principal", "connection")
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.authorize_in_original_read({
      principal: "principal",
      connection: "connection",
      resource: "run",
      operation: "submit",
    })
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.issue_epoch_in_original_read(
      "principal", "connection", "scope", 0.0,
    )
    is Err(OriginalResourceScopePending),
  )
  let runtime = local_runtime_empty(None)
  assert_true(
    capture.bind_packaged_runtime_in_original_read(
      runtime, "principal", "connection", "environment.json", "run.json", "runtime.json",
    )
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.require_packaged_runtime_upgrade_in_original_read()
    is Err(OriginalResourceScopePending),
  )
  assert_true(capture.original_host().unwrap().packaged_runtime is None)
  runtime.close().unwrap()
  // Refusing an unrelated operational route does not rewrite the original
  // ordinary Host's current checks or turn it into a scoped original.
  assert_eq(capture.check_current().issue_family(), 0)
  assert_true(capture.original_resources is None)
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_eq(capture.close().issue_family(), 0)
  let library = capture.library.unwrap()
  // The explicit legacy Library is not the selected-component checked-close
  // route. A descriptor ACK cannot promote it to that separate physical ACK.
  assert_true(library.close_checked() is Err(Physical(_)))
  (library, capture.crypto)
}

///|
fn preparation_read_scope_stop() -> (@sqlite.Library, @crypto.Library) raise {
  let capture = journal_capture_fixture("preparation-scope-stop")
  assert_eq(capture.open().issue_family(), 0)
  let host = capture.original_host().unwrap()
  let database = host.database
  let before = database.read("client_local_adoption", "adoption").unwrap()
  capture.finish_pending_original_scope().unwrap()
  assert_true(capture.closing)
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_eq(capture.open().issue_family(), 3)
  assert_true(
    capture.with_original_read(fn(_host) { "must not run" })
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.require_packaged_runtime_upgrade_in_original_read()
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.authority_scope_cid_in_original_read("principal", "connection")
    is Err(OriginalResourceScopePending),
  )
  assert_true(
    capture.authorize_in_original_read({
      principal: "principal",
      connection: "connection",
      resource: "run",
      operation: "submit",
    })
    is Err(OriginalResourceScopePending),
  )
  assert_eq(
    database.read("client_local_adoption", "adoption").unwrap().body,
    before.body,
  )
  adoption_open_require_locked(host.session.parent)
  assert_eq(capture.close().issue_family(), 0)
  assert_true(capture.descriptor_cleanup_acknowledged())
  assert_true(
    database.read("client_local_adoption", "adoption")
    is Err(@sqlite.DatabaseClosed),
  )
  assert_eq(capture.close().issue_family(), 0)
  let library = capture.library.unwrap()
  assert_true(library.close_checked() is Err(Physical(_)))
  (library, capture.crypto)
}

///|
test "preparation read refuses an ordinary Host before the callback or selected getters" {
  let (library, crypto) = preparation_read_refusal_without_pair()
  // Returning the helper's aliases cannot turn this legacy fixture into an
  // original selected component or manufacture its missing Library ACK.
  assert_true(library.close_checked() is Err(Physical(_)))
  crypto.close_checked().unwrap()
}

///|
test "finishing a captured scope fences new work without acknowledging original DB or lock retirement" {
  let (library, crypto) = preparation_read_scope_stop()
  assert_true(library.close_checked() is Err(Physical(_)))
  crypto.close_checked().unwrap()
}

///|
// Actual inactive routing metadata can precede open. A legacy Library still
// cannot acquire the paired Read or initialize a Journal through this entrance.
test "prepared read refuses a missing pair and retires inactive routing without opening" {
  let capture = journal_capture_fixture("read-unopened-routing")
  let session = capture.original_session()
  let library = capture.library.unwrap()
  let runtime = local_runtime_empty(None)
  let routing = prepare_native_local_run_observation_store_operation(
    capture, runtime, library,
  ).unwrap()
  assert_false(routing.pending_scope().unwrap())
  let calls = Ref(0)
  assert_true(
    capture.with_original_read(fn(_host) { calls.val += 1 })
    is Err(InvalidInput),
  )
  assert_eq(calls.val, 0)
  assert_true(capture.original_host() is None)
  assert_true(capture.original_failure() is None)
  assert_eq(capture.check_current().issue_family(), 1)
  assert_eq(session.root.inspect_generation("client.sqlite3").unwrap(), None)
  routing.close_checked().unwrap()
  assert_false(session.closed)
  adoption_open_require_locked(session.parent)
  assert_eq(capture.close().issue_family(), 0)
  runtime.close().unwrap()
  assert_true(library.close_checked() is Err(Physical(_)))
  capture.crypto.close_checked().unwrap()
}
