///|
fn epoch_test_database(name : String) -> @sqlite.Database {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  library.open_database(root + "/" + name + ".sqlite3", 65536L).unwrap()
}

///|
fn epoch_test_crypto() -> @crypto.Library {
  @crypto.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
}

///|
test "Native epoch authentication and expiry watermark survive SQLite reopen" {
  let first = epoch_test_database("client-epoch-reopen")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(first, crypto).unwrap()
  let authority = open_native_client_epoch_authority(first, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let wire = native_client_submission_epoch_wire(epoch)
  assert_eq(
    authority.verify_epoch(epoch, scope, true, 1001.0).unwrap(),
    @scope.Admissible,
  )
  assert_eq(
    authority.verify_epoch(epoch, scope, true, 1100.0).unwrap(),
    @scope.Expired,
  )
  first.close_checked().unwrap()
  let second = epoch_test_database("client-epoch-reopen")
  let restored = open_native_client_epoch_authority(second, crypto, 100.0).unwrap()
  let epoch = admit_native_client_submission_epoch(wire).unwrap()
  // Wall-clock rollback cannot renew admission. Authenticated lookup may still
  // use the original expired identity without issuing another Submission.
  assert_eq(
    restored.verify_epoch(epoch, scope, true, 1001.0).unwrap(),
    @scope.Expired,
  )
  assert_true(
    initialize_native_client_epoch_authority(second, crypto)
    is Err(AlreadyInitialized),
  )
  second.close_checked().unwrap()
}

///|
test "Native epoch authentication binds every body field and current authority" {
  let database = epoch_test_database("client-epoch-binding")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let wire = native_client_submission_epoch_wire(epoch)
  let changed_scope = "sha256:" + "b".repeat(64)
  let body = @decode.open_object(
    epoch_cursor(@scope.submission_epoch_wire(epoch.body)).unwrap(),
  ).unwrap()
  let nonce = epoch_text(body, "epoch_nonce").unwrap()
  let nonce_bytes = epoch_hex_bytes(nonce).unwrap()
  let changed_nonce = epoch_hex(
    Bytes::makei(32, i => {
      if i == 0 {
        nonce_bytes[i] ^ 1
      } else {
        nonce_bytes[i]
      }
    }),
  )
  let changed_tag = epoch_hex(
    Bytes::makei(32, i => if i == 0 { epoch.tag[i] ^ 1 } else { epoch.tag[i] }),
  )
  for
    changed in [
      wire.replace(old=scope, new=changed_scope),
      wire.replace(old=nonce, new=changed_nonce),
      wire.replace(old=epoch_hex(epoch.tag), new=changed_tag),
      wire.replace(old="\"expiresAt\":1100", new="\"expiresAt\":1200"),
      wire.replace(old="\"notBefore\":1000", new="\"notBefore\":999"),
    ] {
    let altered = admit_native_client_submission_epoch(changed).unwrap()
    assert_true(
      authority.verify_epoch(altered, scope, true, 1001.0) is Err(Unverifiable),
    )
  }
  assert_true(
    authority.verify_epoch(epoch, changed_scope, true, 1001.0)
    is Err(ScopeMismatch),
  )
  assert_true(
    authority.verify_epoch(epoch, scope, false, 1001.0)
    is Err(AuthorizationDenied),
  )
  assert_true(
    authority.issue_epoch(scope, false, 1001.0) is Err(AuthorizationDenied),
  )
  assert_true(
    admit_native_client_submission_epoch(
      wire.replace(old="\"version\":", new="\"foreign\":0,\"version\":"),
    )
    is Err(Unverifiable),
  )
  assert_true(
    admit_native_client_submission_epoch(
      wire.replace(
        old="\"notBefore\":1000",
        new="\"notBefore\":1000,\"notBefore\":1000",
      ),
    )
    is Err(Unverifiable),
  )
  let altered = admit_native_client_submission_epoch(
    wire.replace(old=epoch_hex(epoch.tag), new=changed_tag),
  ).unwrap()
  assert_true(
    authority.verify_epoch(altered, scope, true, 1200.0) is Err(Unverifiable),
  )
  assert_eq(
    authority.verify_epoch(epoch, scope, true, 1001.0).unwrap(),
    @scope.Expired,
  )
  database.close_checked().unwrap()
}

///|
test "Native epoch custody loss is refused and never creates replacement keys" {
  let database = epoch_test_database("client-epoch-custody")
  let crypto = epoch_test_crypto()
  assert_true(
    open_native_client_epoch_authority(database, crypto, 100.0)
    is Err(CustodyLost),
  )
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let retained = database.read("client_submission_epoch", "authority").unwrap()
  ignore(
    database
    .compare_exchange(
      "client_submission_epoch",
      "authority",
      retained.revision,
      b"{\"version\":\"actql-native-submission-epoch-custody/0.1\"}",
    )
    .unwrap(),
  )
  assert_true(
    authority.verify_epoch(epoch, scope, true, 1001.0) is Err(CustodyLost),
  )
  assert_true(
    open_native_client_epoch_authority(database, crypto, 100.0)
    is Err(CustodyLost),
  )
  assert_true(
    initialize_native_client_epoch_authority(database, crypto)
    is Err(AlreadyInitialized),
  )
  database.close_checked().unwrap()
}

///|
test "epoch verification consumes one custody read and preserves a no-op durable watermark" {
  let database = epoch_test_database("epoch-once-watermark")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let original = database.read("client_submission_epoch", "authority").unwrap()
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  assert_eq(
    authority
    .verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Admissible,
  )
  assert_eq(
    calls
    .filter(value => value == "read:client_submission_epoch:authority")
    .length(),
    1,
  )
  assert_false(calls.any(value => value.has_prefix("compare_exchange:")))
  let retained = database.read("client_submission_epoch", "authority").unwrap()
  assert_eq(retained.revision, original.revision)
  assert_eq(retained.body, original.body)
  calls.clear()
  assert_eq(
    authority
    .verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1100.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Expired,
  )
  assert_eq(
    calls
    .filter(value => value == "read:client_submission_epoch:authority")
    .length(),
    1,
  )
  assert_eq(
    calls
    .filter(value => {
      value == "compare_exchange:client_submission_epoch:authority"
    })
    .length(),
    1,
  )
  let advanced = database.read("client_submission_epoch", "authority").unwrap()
  assert_eq(advanced.revision, original.revision + 1L)
  calls.clear()
  // An earlier caller clock cannot renew this already expired original.
  assert_eq(
    authority
    .verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1001.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Expired,
  )
  assert_false(calls.any(value => value.has_prefix("compare_exchange:")))
  assert_eq(
    database.read("client_submission_epoch", "authority").unwrap().revision,
    advanced.revision,
  )
  calls.clear()
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      scope,
      false,
      1001.0,
      operations=Some(operations),
    )
    is Err(AuthorizationDenied),
  )
  assert_eq(calls.length(), 0)
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "no-op watermark commit loss remains Unknown and fences its original handle" {
  let database = epoch_test_database("epoch-noop-commit-unknown")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  submitted_test_fail_commit_after(database, 0, true)
  assert_true(
    authority.verify_epoch(epoch, scope, true, 1000.0)
    is Err(TransactionUnknown),
  )
  assert_true(database.transaction_fenced())
  assert_true(authority.verify_epoch(epoch, scope, true, 1000.0) is Err(Fenced))
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}
