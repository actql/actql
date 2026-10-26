///|
// Real disposable SQLite only. This exercises finite role-specific storage;
// it supplies no initial Host/key authority, signature or Resolution admission.
fn initial_host_signing_storage_fixture(
  name : String,
) -> (
  @sqlite.Library,
  @sqlite.Database,
  @credential.LocalSigningCredentialGrant,
) {
  let (library, db, _, _) = original_signing_claim_fixture(name)
  let scope = {
    ..owned_signing_scope_fixture(),
    purpose: @credential.HostAttestation,
  }
  let grant = @credential.prepare_local_signing_credential_grant(
    "fixture-issuer", scope, 10000L, 1,
  ).unwrap()
  (library, db, grant)
}

///|
test "initial Host use keeps Reviewer entries closed and claims only its one exact original" {
  let (library, db, grant) = initial_host_signing_storage_fixture(
    "initial-host-role",
  )
  let scope = @credential.local_signing_credential_grant_scope(grant)
  db.begin_immediate().unwrap()
  assert_true(
    claim_native_local_original_signing_use_in_transaction(
      db, grant, scope, 100L,
    )
    is Err(Credential(_)),
  )
  let use = claim_native_local_initial_host_signing_use_in_transaction(
    db, grant, scope, 100L,
  ).unwrap()
  db.commit().unwrap()
  assert_true(
    prepare_native_local_original_signing_history_candidate(db, grant)
    is Err(Credential(_)),
  )
  let history = prepare_native_local_initial_host_signing_history_candidate(
    db, grant,
  ).unwrap()
  assert_true(history.observed_outcome() == Claimed)
  assert_eq(
    @credential.local_signing_credential_use_json(history.original_use()),
    @credential.local_signing_credential_use_json(use),
  )
  db.begin_immediate().unwrap()
  assert_true(
    check_native_local_original_signing_use_in_transaction(
      db, grant, use, scope, 101L,
    )
    is Err(Credential(_)),
  )
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      use,
      Succeeded,
    )
    is Err(Credential(_)),
  )
  check_native_local_initial_host_signing_use_in_transaction(
    db, grant, use, scope, 101L,
  ).unwrap()
  record_native_local_initial_host_signing_outcome_in_transaction(
    db,
    grant,
    use,
    Succeeded,
  ).unwrap()
  |> ignore
  assert_true(
    claim_native_local_initial_host_signing_use_in_transaction(
      db, grant, scope, 101L,
    )
    is Err(UseAlreadyClaimed),
  )
  db.commit().unwrap()
  assert_true(
    prepare_native_local_initial_host_signing_history_candidate(db, grant)
    .unwrap()
    .observed_outcome() ==
    Succeeded,
  )
  let reviewer = @credential.prepare_local_signing_credential_grant(
    "fixture-issuer",
    owned_signing_scope_fixture(),
    10000L,
    1,
  ).unwrap()
  db.begin_immediate().unwrap()
  assert_true(
    claim_native_local_initial_host_signing_use_in_transaction(
      db,
      reviewer,
      owned_signing_scope_fixture(),
      102L,
    )
    is Err(Credential(_)),
  )
  assert_true(
    prepare_native_local_initial_host_signing_history_candidate(db, reviewer)
    is Err(Credential(_)),
  )
  db.rollback().unwrap()
  db.close_checked().unwrap()
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "initial Host Unknown and failed original outcomes never become a fresh use or success" {
  for outcome in [Unknown, Failed] {
    let (library, db, grant) = initial_host_signing_storage_fixture(
      if outcome == Unknown {
        "initial-host-unknown"
      } else {
        "initial-host-failed"
      },
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    db.begin_immediate().unwrap()
    let use = claim_native_local_initial_host_signing_use_in_transaction(
      db, grant, scope, 100L,
    ).unwrap()
    record_native_local_initial_host_signing_outcome_in_transaction(
      db, grant, use, outcome,
    ).unwrap()
    |> ignore
    db.commit().unwrap()
    db.begin_immediate().unwrap()
    assert_true(
      claim_native_local_initial_host_signing_use_in_transaction(
        db, grant, scope, 101L,
      )
      is Err(UseAlreadyClaimed),
    )
    assert_true(
      record_native_local_initial_host_signing_outcome_in_transaction(
        db,
        grant,
        use,
        Succeeded,
      )
      is Err(Journal(@sqlite.Collision)),
    )
    db.rollback().unwrap()
    assert_true(
      prepare_native_local_initial_host_signing_history_candidate(db, grant)
      .unwrap()
      .observed_outcome() ==
      outcome,
    )
    db.close_checked().unwrap()
    assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
  }
}

///|
test "initial Host current refuses expiry revocation and missing durable use without repair" {
  for variant in 0..<3 {
    let (library, db, grant) = initial_host_signing_storage_fixture(
      "initial-host-current-" + variant.to_string(),
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    let cid = @credential.local_signing_credential_grant_cid(grant)
    db.begin_immediate().unwrap()
    let use = claim_native_local_initial_host_signing_use_in_transaction(
      db, grant, scope, 100L,
    ).unwrap()
    db.commit().unwrap()
    if variant == 1 {
      db.insert(revocation_scope(), cid, @utf8.encode(cid)).unwrap() |> ignore
    }
    if variant == 2 {
      let row = db.read(use_scope(cid), scope.attempt_id).unwrap()
      db.begin_immediate().unwrap()
      db
      .remove_exact(use_scope(cid), scope.attempt_id, row.revision, row.body)
      .unwrap()
      db.commit().unwrap()
    }
    db.begin_immediate().unwrap()
    assert_true(
      check_native_local_initial_host_signing_use_in_transaction(
        db,
        grant,
        use,
        scope,
        if variant == 0 {
          10000L
        } else {
          101L
        },
      )
      is Err(_),
    )
    assert_true(
      claim_native_local_initial_host_signing_use_in_transaction(
        db, grant, scope, 101L,
      )
      is Err(_),
    )
    db.rollback().unwrap()
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
      Some(1L),
    )
    db.close_checked().unwrap()
    assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
  }
}
