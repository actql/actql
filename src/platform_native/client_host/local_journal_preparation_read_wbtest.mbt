///|
// An ordinary legacy Library fixture cannot acquire the original Read route.
// These are actual Journal/descriptor refusal tests, not a funded pair positive.
fn preparation_read_refusal_without_pair() -> (@sqlite.Library, @crypto.Library) raise {
  let capture = journal_capture_fixture("preparation-without-original-read")
  assert_eq(capture.open().issue_family(), 0)
  let calls = Ref(0)
  assert_true(
    capture.with_original_read(fn(_host) {
      calls.val += 1
      "must not run"
    })
    is Err(InvalidInput),
  )
  assert_eq(calls.val, 0)
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
