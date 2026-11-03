///|
// Independent identity controls. This is not an adopted Host or a Provider call.
test "Raw journal lookup refuses another preparation target attempt or mutation scope" {
  let scope = native_preparation_identity_scope()
  let grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", scope, 2000000000000L, 2,
  ).unwrap()
  assert_true(local_preparation_raw_lookup_scope_matches(grant, scope))
  for
    changed in [
      { ..scope, attempt_id: "foreign-attempt", },
      { ..scope, principal: "foreign-principal", },
      { ..scope, request_path: scope.request_path + "-foreign", },
      { ..scope, request_method: "PATCH", },
      { ..scope, operation: "salesforce:record:update", },
      { ..scope, host_adoption_cid: credential_test_cid("a"), },
      { ..scope, operation_occurrence_cid: credential_test_cid("b"), },
    ] {
    assert_false(local_preparation_raw_lookup_scope_matches(grant, changed))
  }
}

///|
// This fixture creates original low-level records, never an operational Host
// grant ACK. All physical libraries and its isolated root must be explicit.
fn raw_lookup_native_fixture(
  label : String,
) -> (
  @sqlite.Database,
  @sqlite.Library,
  String,
  @publication.Store,
  @publication.LocalPreparationRawCustody,
  NativeLocalPreparationRawStore,
  @credential.LocalPreparationCredentialGrant,
  @credential.LocalPreparationCredentialScope,
)? {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(crypto_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(http_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET") is Some(secret) else {
    if @env.get_env_var("ACTQL_REQUIRE_NATIVE_LOCAL_RAW_LOOKUP_TESTS") ==
      Some("1") {
      abort(
        "raw lookup requires its actual isolated SQLite/crypto/HTTP fixture",
      )
    }
    return None
  }
  let directory = label + "-" + @env.now().to_string()
  let root = @filesystem.open_private_root(root_path).unwrap()
  root.create_directory(directory).unwrap() |> ignore
  // The original credential Journal and Publication Store own sibling roots.
  // A fresh Store must not inherit the unmarked Journal database as its format.
  let store_directory = directory + "-publication"
  root.create_directory(store_directory).unwrap() |> ignore
  let store_root = root_path + "/" + store_directory
  let journal_path = root_path + "/" + directory + "/original-credential.sqlite"
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let database = sqlite.open_database(journal_path, 65536L).unwrap()
  let crypto = @signature.load_library(crypto_path).unwrap()
  let store = @publication.open_store(
    sqlite,
    store_root,
    credential_test_cid("a"),
    65536L,
    8L,
    65536L,
  ).unwrap()
  let http = @http.load_library(http_path).unwrap()
  let client = http
    .create_authenticated_client(ca, @http.Bearer(secret), 16L, 2000, 5000)
    .unwrap()
  let scope = native_preparation_identity_scope()
  let grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", scope, 2000000000000L, 2,
  ).unwrap()
  let original_use = @credential.prepare_local_preparation_credential_use(
    grant, "observe-use", 1999999999999L, 0, false, scope,
  ).unwrap()
  let grant_cid = @credential.local_preparation_credential_grant_cid(grant)
  guard database.claim_ordinal_action(use_scope(grant_cid), "observe-use", 2L)
    is Ok(@sqlite.Fresh(1L)) else {
    abort("raw lookup fixture did not create its original ordinal")
  }
  database
  .insert(
    use_scope(grant_cid),
    "observe-use",
    @utf8.encode(
      "sha256:17f393ef1ac8c8fd7d86ddb27ae3f62869b6d3391bf1a1c040b10df8169443f8\n" +
      @credential.local_preparation_credential_use_json(original_use).unwrap(),
    ),
  )
  .unwrap()
  |> ignore
  database
  .insert(outcome_scope(grant_cid), "observe-use", b"unknown\n")
  .unwrap()
  |> ignore
  let key = Bytes::makei(32, i => i.to_byte())
  let custody = store
    .prepare_local_preparation_raw_observation(
      grant, original_use, client, crypto, key,
    )
    .unwrap()
  custody.reserve().unwrap()
  custody.persist(401, @utf8.encode("e\u0301\r\n")).unwrap()
  let raw = bind_native_local_preparation_raw_store(store, crypto, key).unwrap()
  // The read view never receives this transport or its secret. Confirm its
  // close before any lookup; no Provider method is invoked by this fixture.
  if !client.close() {
    abort("raw lookup fixture did not close its HTTP client")
  }
  Some((database, sqlite, journal_path, store, custody, raw, grant, scope))
}

///|
test "Raw journal lookup reopens original unknown use without transport or outcome repair" {
  guard raw_lookup_native_fixture("raw-journal-reopen")
    is Some((database, sqlite, path, store, custody, raw, grant, scope)) else {
    return
  }
  let grant_cid = @credential.local_preparation_credential_grant_cid(grant)
  let original_row = database.read(use_scope(grant_cid), "observe-use").unwrap()
  let original_capacity = store.capacity_usage().unwrap()
  database.close_checked().unwrap()
  let reopened = sqlite.open_existing_database(path, 65536L).unwrap()
  let stages : Array[String] = []
  let view = bind_native_local_preparation_raw_lookup_with_clock(
    reopened,
    raw,
    grant,
    scope,
    facts => {
      stages.push(facts.stage)
      facts.scope == scope && facts.grant_cid == grant_cid
    },
    () => true,
    () => 1999999999999L,
  ).unwrap()
  for _ in 0..<2 {
    let result = view.lookup("observe-use").unwrap()
    assert_eq(result.original_use.outcome, "unknown")
    assert_eq(result.original_use.status, None)
    assert_eq(
      result.original_use.use_cid,
      "sha256:17f393ef1ac8c8fd7d86ddb27ae3f62869b6d3391bf1a1c040b10df8169443f8",
    )
    assert_eq(result.observation.status, 401)
    assert_eq(result.observation.body, @utf8.encode("e\u0301\r\n"))
    assert_eq(
      reopened.read(use_scope(grant_cid), "observe-use").unwrap().body,
      original_row.body,
    )
    assert_eq(
      reopened.read(outcome_scope(grant_cid), "observe-use").unwrap().body,
      b"unknown\n",
    )
    assert_eq(
      store.capacity_usage().unwrap().reserved_bytes,
      original_capacity.reserved_bytes,
    )
  }
  assert_eq(stages, [
    "query", "raw-query", "raw-return", "query", "raw-query", "raw-return",
  ])
  assert_true(
    view.lookup("missing-original-use") is Err(Journal(@sqlite.NotFound)),
  )
  assert_true(
    reopened.read(use_scope(grant_cid), "missing-original-use")
    is Err(@sqlite.NotFound),
  )
  assert_true(custody.retry_cleanup().unwrap())
  assert_false(custody.retry_cleanup().unwrap())
  assert_true(
    view.lookup("observe-use")
    is Err(RawObservation(@publication.RecoveryRequired)),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 0L)
  store.close().unwrap() |> ignore
  // Delayed metadata return rechecks the same original use/fence after Store
  // cleanup. It does not restore the deleted raw slot or read the body again.
  view.authorize_return("observe-use").unwrap()
  assert_eq(
    reopened.read(outcome_scope(grant_cid), "observe-use").unwrap().body,
    b"unknown\n",
  )
  assert_eq(
    reopened.read(use_scope(grant_cid), "observe-use").unwrap().body,
    original_row.body,
  )
  assert_true(
    view.authorize_return("missing-original-use")
    is Err(Journal(@sqlite.NotFound)),
  )
  reopened.close_checked().unwrap()
}

///|
test "Raw journal lookup refuses current denial expiry and revocation after callbacks" {
  guard raw_lookup_native_fixture("raw-journal-current")
    is Some((database, _, _, store, custody, raw, grant, scope)) else {
    return
  }
  let grant_cid = @credential.local_preparation_credential_grant_cid(grant)
  let stages : Array[String] = []
  let denied = bind_native_local_preparation_raw_lookup_with_clock(
    database,
    raw,
    grant,
    scope,
    facts => {
      stages.push(facts.stage)
      false
    },
    () => true,
    () => 1999999999999L,
  ).unwrap()
  assert_true(denied.lookup("observe-use") is Err(AccessDenied))
  assert_eq(stages, ["query"])
  assert_true(denied.authorize_return("observe-use") is Err(AccessDenied))
  let stopped = bind_native_local_preparation_raw_lookup_with_clock(
    database,
    raw,
    grant,
    scope,
    _ => true,
    () => false,
    () => 1999999999999L,
  ).unwrap()
  assert_true(stopped.lookup("observe-use") is Err(AccessDenied))
  assert_true(stopped.authorize_return("observe-use") is Err(AccessDenied))
  let expired_grant = @credential.prepare_local_preparation_credential_grant(
    "local-authority-a", scope, 1999999999999L, 2,
  ).unwrap()
  let expired = bind_native_local_preparation_raw_lookup_with_clock(
    database,
    raw,
    expired_grant,
    scope,
    _ => true,
    () => true,
    () => 1999999999999L,
  ).unwrap()
  // Expiry is refused before reading a use or raw slot for this grant. This
  // case is independent of the subsequent revocation of the original grant.
  assert_true(
    expired.lookup("observe-use")
    is Err(Credential(@credential.CredentialGrantInactive)),
  )
  assert_true(
    expired.authorize_return("observe-use")
    is Err(Credential(@credential.CredentialGrantInactive)),
  )
  let revoked = bind_native_local_preparation_raw_lookup_with_clock(
    database,
    raw,
    grant,
    scope,
    facts => {
      if facts.stage == "raw-return" {
        database
        .insert(revocation_scope(), grant_cid, @utf8.encode(grant_cid))
        .unwrap()
        |> ignore
      }
      true
    },
    () => true,
    () => 1999999999999L,
  ).unwrap()
  assert_true(
    revoked.lookup("observe-use")
    is Err(Credential(@credential.CredentialGrantInactive)),
  )
  assert_true(
    revoked.authorize_return("observe-use")
    is Err(Credential(@credential.CredentialGrantInactive)),
  )
  assert_eq(
    database.read(outcome_scope(grant_cid), "observe-use").unwrap().body,
    b"unknown\n",
  )
  assert_eq(custody.confirm().unwrap().body, @utf8.encode("e\u0301\r\n"))
  assert_true(custody.retry_cleanup().unwrap())
  database.close_checked().unwrap()
  store.close().unwrap() |> ignore
}
