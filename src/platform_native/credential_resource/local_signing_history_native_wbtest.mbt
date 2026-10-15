///|
// Fresh real SQLite metadata only. No secret, signer, issuer, HTTP client,
// original operational Run or authorization supplier is constructed here.
fn signing_history_fixture(
  name : String,
) -> (
  @sqlite.Library,
  @sqlite.Database,
  String,
  @credential.LocalSigningCredentialGrant,
) {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(128),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" +
    name +
    ".sqlite3"
  let database = library.open_database(path, 8192L).unwrap()
  let grant = @credential.prepare_local_signing_credential_grant(
    "original-host-issuer",
    owned_signing_scope_fixture(),
    1791970559138L,
    2,
  ).unwrap()
  (library, database, path, grant)
}

///|
fn signing_history_fixture_use(
  grant : @credential.LocalSigningCredentialGrant,
  use_id : String,
  ordinal : Int,
) -> @credential.LocalSigningCredentialUse {
  @credential.prepare_local_signing_credential_use(
    grant,
    use_id,
    1791970559137L,
    ordinal - 1,
    false,
    @credential.local_signing_credential_grant_scope(grant),
  ).unwrap()
}

///|
fn signing_history_fixture_store_use(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  use_id : String,
  ordinal : Int,
) -> @credential.LocalSigningCredentialUse {
  let original = signing_history_fixture_use(grant, use_id, ordinal)
  database
  .insert(
    use_scope(@credential.local_signing_credential_grant_cid(grant)),
    use_id,
    @utf8.encode(
      @credential.local_signing_credential_use_cid(original) +
      "\n" +
      @credential.local_signing_credential_use_json(original).unwrap(),
    ),
  )
  .unwrap()
  |> ignore
  original
}

///|
test "Signing history candidate requires the durable original claim before copied use metadata" {
  let (_, database, _, grant) = signing_history_fixture("sign-history-claim")
  let cid = @credential.local_signing_credential_grant_cid(grant)
  signing_history_fixture_store_use(database, grant, "original", 1) |> ignore
  assert_true(
    prepare_native_local_signing_history_candidate(database, grant, "original")
    is Err(Journal(@sqlite.NotFound)),
  )
  assert_eq(
    database.lookup_claim_ordinal(use_scope(cid), "original").unwrap(),
    None,
  )
  assert_true(
    database.claim_ordinal_action(use_scope(cid), "other", 2L)
    is Ok(@sqlite.Fresh(1L)),
  )
  database.close_checked().unwrap()
}

///|
test "Signing history candidate keeps missing use unavailable without reclaim or repair" {
  let (_, database, _, grant) = signing_history_fixture("sign-history-use")
  let scope = use_scope(@credential.local_signing_credential_grant_cid(grant))
  assert_eq(database.claim_ordinal(scope, "original", 2L).unwrap(), 1L)
  assert_true(
    prepare_native_local_signing_history_candidate(database, grant, "original")
    is Err(Journal(@sqlite.NotFound)),
  )
  assert_eq(database.lookup_claim_ordinal(scope, "original").unwrap(), Some(1L))
  assert_true(database.read(scope, "original") is Err(@sqlite.NotFound))
  assert_true(
    database.claim_ordinal_action(scope, "next", 2L) is Ok(@sqlite.Fresh(2L)),
  )
  database.close_checked().unwrap()
}

///|
test "Signing history candidate reopens exact unknown custody without renewing expiry" {
  let (library, database, path, grant) = signing_history_fixture(
    "sign-history-restart",
  )
  let cid = @credential.local_signing_credential_grant_cid(grant)
  database.claim_ordinal(use_scope(cid), "original", 2L).unwrap() |> ignore
  let original = signing_history_fixture_store_use(
    database, grant, "original", 1,
  )
  database.insert(outcome_scope(cid), "original", b"unknown\n").unwrap()
  |> ignore
  let use_row = database.read(use_scope(cid), "original").unwrap()
  let outcome_row = database.read(outcome_scope(cid), "original").unwrap()
  database.close_checked().unwrap()
  let reopened = library.open_existing_database(path, 8192L).unwrap()
  for _ in 0..<2 {
    let candidate = prepare_native_local_signing_history_candidate(
      reopened, grant, "original",
    ).unwrap()
    assert_eq(candidate.grant_cid(), cid)
    assert_eq(
      @credential.local_signing_credential_use_cid(candidate.original_use()),
      @credential.local_signing_credential_use_cid(original),
    )
    assert_true(candidate.observed_outcome() == Unknown)
  }
  assert_eq(
    reopened.read(use_scope(cid), "original").unwrap().body,
    use_row.body,
  )
  assert_eq(
    reopened.read(outcome_scope(cid), "original").unwrap().body,
    outcome_row.body,
  )
  assert_eq(reopened.read(use_scope(cid), "original").unwrap().revision, 0L)
  assert_eq(
    reopened.lookup_claim_ordinal(use_scope(cid), "original").unwrap(),
    Some(1L),
  )
  // History inspection does not call the independent use gate or renew it.
  assert_true(
    authorize_owned_credential_use(
      SigningUse(original),
      1791970559138L,
      false,
      SigningScope(@credential.local_signing_credential_grant_scope(grant)),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  reopened.close_checked().unwrap()
}

///|
test "Signing history candidate distinguishes claimed and exact terminal tags without HTTP status" {
  for
    (name, outcome) in [
      ("succeeded", Succeeded),
      ("failed", Failed),
      ("unknown", Unknown),
    ] {
    let (_, database, _, grant) = signing_history_fixture(
      "sign-history-" + name,
    )
    let cid = @credential.local_signing_credential_grant_cid(grant)
    database.claim_ordinal(use_scope(cid), "original", 2L).unwrap() |> ignore
    signing_history_fixture_store_use(database, grant, "original", 1) |> ignore
    assert_true(
      prepare_native_local_signing_history_candidate(
        database, grant, "original",
      )
      .unwrap()
      .observed_outcome() ==
      Claimed,
    )
    database
    .insert(outcome_scope(cid), "original", @utf8.encode(name + "\n"))
    .unwrap()
    |> ignore
    assert_true(
      prepare_native_local_signing_history_candidate(
        database, grant, "original",
      )
      .unwrap()
      .observed_outcome() ==
      outcome,
    )
    database.close_checked().unwrap()
  }
}

///|
test "Signing history candidate refuses changed grant use ordinal and mutable original" {
  let (_, database, _, grant) = signing_history_fixture("sign-history-bindings")
  let cid = @credential.local_signing_credential_grant_cid(grant)
  let scope = use_scope(cid)
  database.claim_ordinal(scope, "original", 2L).unwrap() |> ignore
  let original = signing_history_fixture_store_use(
    database, grant, "original", 2,
  )
  assert_true(
    prepare_native_local_signing_history_candidate(database, grant, "original")
    is Err(Journal(@sqlite.Collision)),
  )
  let same_body = database.read(scope, "original").unwrap().body
  database.compare_exchange(scope, "original", 0L, same_body).unwrap() |> ignore
  assert_true(
    prepare_native_local_signing_history_candidate(database, grant, "original")
    is Err(Journal(@sqlite.Collision)),
  )
  let changed = @credential.prepare_local_signing_credential_grant(
    "other-issuer",
    @credential.local_signing_credential_grant_scope(grant),
    1791970559138L,
    2,
  ).unwrap()
  assert_true(
    prepare_native_local_signing_history_candidate(
      database, changed, "original",
    )
    is Err(Journal(@sqlite.NotFound)),
  )
  assert_true(
    prepare_native_local_signing_history_candidate(
      database, grant, "foreign-use",
    )
    is Err(Journal(@sqlite.NotFound)),
  )
  assert_eq(@credential.local_signing_credential_use_projection(original).2, 2)
  assert_eq(database.lookup_claim_ordinal(scope, "original").unwrap(), Some(1L))
  database.close_checked().unwrap()
}

///|
test "Signing history candidate refuses malformed status and replaced outcome instead of repairing it" {
  for
    index, body in [
      b"unknown\n200", b"succeeded\n200", b"unknown", b"claimed\n", b"unknown\n\n",
    ] {
    let (_, database, _, grant) = signing_history_fixture(
      "sign-history-bad-" + index.to_string(),
    )
    let cid = @credential.local_signing_credential_grant_cid(grant)
    database.claim_ordinal(use_scope(cid), "original", 2L).unwrap() |> ignore
    signing_history_fixture_store_use(database, grant, "original", 1) |> ignore
    database.insert(outcome_scope(cid), "original", body).unwrap() |> ignore
    assert_true(
      prepare_native_local_signing_history_candidate(
        database, grant, "original",
      )
      is Err(Journal(@sqlite.Collision)),
    )
    assert_eq(database.read(outcome_scope(cid), "original").unwrap().body, body)
    database.close_checked().unwrap()
  }
  let (_, database, _, grant) = signing_history_fixture("sign-history-replaced")
  let cid = @credential.local_signing_credential_grant_cid(grant)
  database.claim_ordinal(use_scope(cid), "original", 2L).unwrap() |> ignore
  signing_history_fixture_store_use(database, grant, "original", 1) |> ignore
  database.insert(outcome_scope(cid), "original", b"unknown\n").unwrap()
  |> ignore
  database
  .compare_exchange(outcome_scope(cid), "original", 0L, b"unknown\n")
  .unwrap()
  |> ignore
  assert_true(
    prepare_native_local_signing_history_candidate(database, grant, "original")
    is Err(Journal(@sqlite.Collision)),
  )
  database.close_checked().unwrap()
}
