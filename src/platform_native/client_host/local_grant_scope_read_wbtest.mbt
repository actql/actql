///|
test "initial grant scope keeps legacy projection but refuses a selected inactive Read" {
  let capture = journal_capture_fixture("initial-grant-scope-inactive")
  assert_eq(capture.open().issue_family(), 0)
  let host = capture.original_host().unwrap()
  let expected = host
    .authority_scope_cid("principal", "connection", capture.crypto)
    .unwrap()
  assert_true(expected.has_prefix("sha256:"))
  // A genuine legacy Host is not an entered paired Read. Selecting it must
  // refuse, rather than silently returning the unscoped fallback above.
  assert_true(
    host.authority_scope_cid(
      "principal",
      "connection",
      capture.crypto,
      capture=Some(capture),
    )
    is Err(OriginalResourceScopePending),
  )
  assert_eq(capture.close().issue_family(), 0)
  assert_true(capture.library.unwrap().close_checked() is Err(Physical(_)))
  capture.crypto.close_checked().unwrap()
}

///|
test "initial grant scope refuses a foreign original Host or Crypto before projection" {
  // The existing adoption lock belongs to the parent Root, not the state
  // directory. These actual foreign owners need distinct original parents.
  let capture = submit_scope_current_capture(
    "initial-grant-scope-owner", local_selected_account,
  )
  let foreign = submit_scope_current_capture(
    "initial-grant-scope-foreign", local_selected_account,
  )
  assert_eq(capture.open().issue_family(), 0)
  assert_eq(foreign.open().issue_family(), 0)
  let host = capture.original_host().unwrap()
  assert_true(
    host.authority_scope_cid(
      "principal",
      "connection",
      capture.crypto,
      capture=Some(foreign),
    )
    is Err(CustodyLost),
  )
  assert_true(
    host.authority_scope_cid(
      "principal",
      "connection",
      foreign.crypto,
      capture=Some(capture),
    )
    is Err(CustodyLost),
  )
  assert_eq(foreign.close().issue_family(), 0)
  assert_eq(capture.close().issue_family(), 0)
  assert_true(foreign.library.unwrap().close_checked() is Err(Physical(_)))
  assert_true(capture.library.unwrap().close_checked() is Err(Physical(_)))
  foreign.crypto.close_checked().unwrap()
  capture.crypto.close_checked().unwrap()
}
