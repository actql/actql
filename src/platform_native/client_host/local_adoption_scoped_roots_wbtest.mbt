///|
// A failed test cleanup retains its exact Session rather than treating stack
// unwinding or process exit as an original descriptor acknowledgement.
let scoped_adoption_pending_session : Ref[NativeLocalAdoptionSession?] = Ref(None)

///|
fn scoped_adoption_close_session(session : NativeLocalAdoptionSession) -> Unit raise {
  assert_true(scoped_adoption_pending_session.val is None)
  scoped_adoption_pending_session.val = Some(session)
  assert_true(session.close())
  close_local_session_owned_root_descriptors(session).unwrap()
  scoped_adoption_pending_session.val = None
}

///|
fn scoped_adoption_refusal(
  value : Result[NativeLocalAdoptionSession, NativeLocalAdoptionOpenFailure],
) -> NativeLocalAdoptionOpenFailure raise {
  match value {
    Err(original) => original
    Ok(session) => {
      scoped_adoption_close_session(session)
      fail("missing original read context acquired a Session")
      abort("unreachable")
    }
  }
}

///|
test "scoped existing adoption refuses before acquiring Roots and preserves the actual legacy original" {
  let name = "scoped-existing-unselected"
  let seeded = local_journal_test_connection(name)
  let intent = seeded.session.intent_cid()
  seeded.close_owned_root_descriptors().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let failed = scoped_adoption_refusal(
    begin_existing_native_local_host_adoption_in_current_read_context_with_custody(
      path,
      name + ".host",
      path,
      name + ".account.json",
      "operator",
      epoch_test_crypto(),
      128,
    ),
  )
  assert_true(failed.issue() is Filesystem(@filesystem.RootOpen(_)))
  assert_true(failed.source_root is None)
  assert_true(failed.parent is None)
  assert_true(failed.root is None)
  assert_true(failed.managed is None)
  assert_true(failed.lock is None)
  assert_true(
    failed.root_acquisition is Some(original) && original.issue() is @filesystem.RootOpen(_),
  )
  failed.retry_cleanup().unwrap()
  failed.retry_cleanup().unwrap()
  assert_true(failed.issue() is Filesystem(@filesystem.RootOpen(_)))
  let restored = begin_existing_native_local_host_adoption_with_custody(
    path,
    name + ".host",
    path,
    name + ".account.json",
    "operator",
    epoch_test_crypto(),
  ).unwrap()
  assert_eq(restored.intent_cid(), intent)
  assert_true(restored.existing_only)
  assert_false(restored.initial_signing_eligible.val)
  restored.check_original().unwrap()
  scoped_adoption_close_session(restored)
}

///|
test "scoped adoption diagnostic bounds cannot select legacy allocation or create an initial Host" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  for ceiling in [-1, 0] {
    let failed = scoped_adoption_refusal(
      begin_existing_native_local_host_adoption_in_current_read_context_with_custody(
        path,
        "scoped-never-created.host",
        path,
        "not-read.account.json",
        "operator",
        epoch_test_crypto(),
        ceiling,
      ),
    )
    assert_true(failed.issue() is Filesystem(@filesystem.InvalidLimit))
    assert_true(failed.source_root is None)
    assert_true(failed.parent is None)
    assert_true(failed.root is None)
    assert_true(failed.lock is None)
    assert_true(
      failed.root_acquisition is Some(original) && original.issue() is @filesystem.InvalidLimit,
    )
    failed.retry_cleanup().unwrap()
  }
  let original = @filesystem.open_private_root(path).unwrap()
  assert_true(
    original.inspect_directory("scoped-never-created.host").unwrap() is None,
  )
  original.close().unwrap()
}

///|
test "scoped root opening cannot omit its original failed-acquisition carrier" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  assert_true(
    local_adoption_open_private_root(
      path,
      None,
      root_opening=CurrentOriginalReadRoots(128),
    )
    is Err(InvalidInput),
  )
}
