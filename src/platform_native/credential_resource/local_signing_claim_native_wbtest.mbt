///|
fn original_signing_claim_fixture(
  name : String,
) -> (
  @sqlite.Library,
  @sqlite.Database,
  String,
  @credential.LocalSigningCredentialGrant,
) {
  let (library, database, path, _) = signing_history_fixture(name)
  let grant = @credential.prepare_local_signing_credential_grant(
    "fixture-issuer",
    owned_signing_scope_fixture(),
    10000L,
    3,
  ).unwrap()
  (library, database, path, grant)
}

///|
fn original_signing_claim_begin(
  db : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  now : Int64,
) -> Result[
  @credential.LocalSigningCredentialUse,
  NativeCredentialResourceIssue,
] {
  claim_native_local_original_signing_use_in_transaction(
    db,
    grant,
    @credential.local_signing_credential_grant_scope(grant),
    now,
  )
}

///|
test "one signing operation with max uses three claims its fixed attempt once and retains history only" {
  for outcome in ["claimed", "unknown", "failed", "succeeded"] {
    let (library, db, path, grant) = original_signing_claim_fixture(
      "signing-claim-one-" + outcome,
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    let cid = @credential.local_signing_credential_grant_cid(grant)
    db.begin_immediate().unwrap()
    let first = original_signing_claim_begin(db, grant, 100L).unwrap()
    assert_eq(
      @credential.local_signing_credential_use_projection(first),
      (cid, scope.attempt_id, 1),
    )
    if outcome != "claimed" {
      db
      .insert(
        outcome_scope(cid),
        scope.attempt_id,
        @utf8.encode(outcome + "\n"),
      )
      .unwrap()
      |> ignore
    }
    db.commit().unwrap()
    let original = db.read(use_scope(cid), scope.attempt_id).unwrap()
    db.close_checked().unwrap()
    let db = library.open_existing_database(path, 8192L).unwrap()
    for _ in 0..<3 {
      db.begin_immediate().unwrap()
      assert_true(
        original_signing_claim_begin(db, grant, 101L) is Err(UseAlreadyClaimed),
      )
      db.rollback().unwrap()
      assert_eq(
        db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
        Some(1L),
      )
    }
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), "another-use").unwrap(),
      None,
    )
    assert_eq(
      db.read(use_scope(cid), scope.attempt_id).unwrap().body,
      original.body,
    )
    assert_eq(db.read(use_scope(cid), scope.attempt_id).unwrap().revision, 0L)
    db.close_checked().unwrap()
  }
}

///|
test "one signing operation refuses missing or corrupt claimed original without consuming a replacement" {
  for corrupt in [false, true] {
    let (_, db, _, grant) = original_signing_claim_fixture(
      if corrupt {
        "signing-claim-corrupt"
      } else {
        "signing-claim-missing"
      },
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    let cid = @credential.local_signing_credential_grant_cid(grant)
    db.claim_ordinal(use_scope(cid), scope.attempt_id, 3L).unwrap() |> ignore
    if corrupt {
      db.insert(use_scope(cid), scope.attempt_id, b"malformed").unwrap()
      |> ignore
    }
    db.begin_immediate().unwrap()
    assert_true(
      original_signing_claim_begin(db, grant, 100L) is Err(Journal(_)),
    )
    db.rollback().unwrap()
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
      Some(1L),
    )
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), "replacement").unwrap(),
      None,
    )
    db.close_checked().unwrap()
  }
}

///|
test "one signing operation rejects a legacy use or orphan outcome and never changes it" {
  for legacy_use in [true, false] {
    let (_, db, _, grant) = original_signing_claim_fixture(
      if legacy_use {
        "signing-claim-legacy"
      } else {
        "signing-claim-outcome"
      },
    )
    let cid = @credential.local_signing_credential_grant_cid(grant)
    let bucket = if legacy_use { use_scope(cid) } else { outcome_scope(cid) }
    db.insert(bucket, "old-original", b"original bytes").unwrap() |> ignore
    db.begin_immediate().unwrap()
    assert_true(
      original_signing_claim_begin(db, grant, 100L)
      is Err(Journal(@sqlite.Collision)),
    )
    db.rollback().unwrap()
    assert_eq(db.read(bucket, "old-original").unwrap().body, b"original bytes")
    assert_eq(
      db
      .lookup_claim_ordinal(
        use_scope(cid),
        @credential.local_signing_credential_grant_scope(grant).attempt_id,
      )
      .unwrap(),
      None,
    )
    db.close_checked().unwrap()
  }
}

///|
test "one signing operation with an older foreign claim rolls back the tentative next ordinal" {
  let (_, db, _, grant) = original_signing_claim_fixture(
    "signing-claim-old-ordinal",
  )
  let cid = @credential.local_signing_credential_grant_cid(grant)
  let scope = @credential.local_signing_credential_grant_scope(grant)
  db.claim_ordinal(use_scope(cid), "legacy-original", 3L).unwrap() |> ignore
  db.begin_immediate().unwrap()
  assert_true(
    original_signing_claim_begin(db, grant, 100L)
    is Err(Journal(@sqlite.Collision)),
  )
  db.rollback().unwrap()
  assert_eq(
    db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
    None,
  )
  assert_eq(
    db.lookup_claim_ordinal(use_scope(cid), "legacy-original").unwrap(),
    Some(1L),
  )
  db.close_checked().unwrap()
}

///|
test "one signing operation refuses expiry revocation foreign scope and autocommit without a use" {
  for variant in 0..<5 {
    let (_, db, _, grant) = original_signing_claim_fixture(
      "signing-claim-refuse-" + variant.to_string(),
    )
    let cid = @credential.local_signing_credential_grant_cid(grant)
    let scope = @credential.local_signing_credential_grant_scope(grant)
    if variant == 1 {
      db.insert(revocation_scope(), cid, @utf8.encode(cid)).unwrap() |> ignore
    }
    if variant != 4 {
      db.begin_immediate().unwrap()
    }
    let actual = claim_native_local_original_signing_use_in_transaction(
      db,
      grant,
      if variant == 2 {
        { ..scope, preimage: "sha256:" + "f".repeat(64), }
      } else {
        scope
      },
      if variant == 0 {
        10000L
      } else if variant == 3 {
        -1L
      } else {
        100L
      },
    )
    assert_true(actual is Err(_))
    if variant != 4 {
      db.rollback().unwrap()
    }
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
      None,
    )
    assert_true(db.scan_after(use_scope(cid), "") is Err(@sqlite.NotFound))
    assert_true(
      db.read("credential-clock-v1", "host-lower-bound")
      is Err(@sqlite.NotFound),
    )
    db.close_checked().unwrap()
  }
}

///|
#borrow(db)
extern "C" fn signing_claim_lose_commit_reply(
  db : @sqlite.Database,
  count : Int,
) -> Unit = "actql_native_sqlite_test_fail_commit_reply"

///|
test "one signing operation lost commit ACK reopens history without another claim or new use" {
  let (library, db, path, grant) = original_signing_claim_fixture(
    "signing-claim-ack-loss",
  )
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let cid = @credential.local_signing_credential_grant_cid(grant)
  db.begin_immediate().unwrap()
  original_signing_claim_begin(db, grant, 100L).unwrap() |> ignore
  signing_claim_lose_commit_reply(db, 1)
  assert_true(db.commit() is Err(_))
  db.fence_transactions()
  db.close_checked().unwrap()
  let restored = library.open_existing_database(path, 8192L).unwrap()
  let history = prepare_native_local_signing_history_candidate(
    restored,
    grant,
    scope.attempt_id,
  ).unwrap()
  assert_true(history.observed_outcome() is Claimed)
  assert_eq(
    @credential.local_signing_credential_use_projection(history.original_use()),
    (cid, scope.attempt_id, 1),
  )
  restored.begin_immediate().unwrap()
  assert_true(
    original_signing_claim_begin(restored, grant, 101L)
    is Err(UseAlreadyClaimed),
  )
  restored.rollback().unwrap()
  assert_eq(
    restored.lookup_claim_ordinal(use_scope(cid), "retry").unwrap(),
    None,
  )
  restored.close_checked().unwrap()
}

///|
test "same attempt text remains scoped by grant and foreign purpose is not a Reviewer use" {
  let (_, db, _, grant) = original_signing_claim_fixture(
    "signing-claim-domains",
  )
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let other = @credential.prepare_local_signing_credential_grant(
    "other-original-issuer", scope, 10000L, 3,
  ).unwrap()
  db.begin_immediate().unwrap()
  original_signing_claim_begin(db, grant, 100L).unwrap() |> ignore
  original_signing_claim_begin(db, other, 100L).unwrap() |> ignore
  db.commit().unwrap()
  for current in [grant, other] {
    let cid = @credential.local_signing_credential_grant_cid(current)
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
      Some(1L),
    )
  }
  let host_scope = { ..scope, purpose: @credential.HostAttestation, }
  let host_grant = @credential.prepare_local_signing_credential_grant(
    "host-issuer", host_scope, 10000L, 3,
  ).unwrap()
  db.begin_immediate().unwrap()
  assert_true(
    claim_native_local_original_signing_use_in_transaction(
      db, host_grant, host_scope, 100L,
    )
    is Err(Credential(@credential.CredentialGrantInactive)),
  )
  db.rollback().unwrap()
  assert_eq(
    db
    .lookup_claim_ordinal(
      use_scope(@credential.local_signing_credential_grant_cid(host_grant)),
      scope.attempt_id,
    )
    .unwrap(),
    None,
  )
  db.close_checked().unwrap()
}
