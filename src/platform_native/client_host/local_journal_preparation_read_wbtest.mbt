///|
// An ordinary legacy Library fixture cannot acquire the original Read route.
// These are actual Journal/descriptor refusal tests, not a funded pair positive.
test "preparation read refuses an ordinary Host before the callback or selected getters" {
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
  // Refusing an unrelated operational route does not rewrite the original
  // ordinary Host's current checks or turn it into a scoped original.
  assert_eq(capture.check_current().issue_family(), 0)
  assert_true(capture.original_resources is None)
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_eq(capture.close().issue_family(), 0)
  capture.library.unwrap().close_checked().unwrap()
  capture.crypto.close_checked().unwrap()
}

///|
test "finishing a captured scope fences new work without acknowledging original DB or lock retirement" {
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
  capture.library.unwrap().close_checked().unwrap()
  capture.crypto.close_checked().unwrap()
}
