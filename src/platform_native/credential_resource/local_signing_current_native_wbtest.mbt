///|
// Actual durable use and clock/revocation state only. These checks issue no
// signature, key, Host current authority, approval or continuation permission.
test "original signing current check joins the same transaction without renewing its use" {
  let (library, db, _, grant) = original_signing_claim_fixture(
    "signing-current-clock",
  )
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let cid = @credential.local_signing_credential_grant_cid(grant)
  let grant_body = @credential.local_signing_credential_grant_json(grant)
  db.begin_immediate().unwrap()
  let original = original_signing_claim_begin(db, grant, 100L).unwrap()
  db.commit().unwrap()
  let use_row = db.read(use_scope(cid), scope.attempt_id).unwrap()
  let clock = db.read("credential-clock-v1", "host-lower-bound").unwrap()
  assert_true(
    check_native_local_original_signing_use_in_transaction(
      db, grant, original, scope, 101L,
    )
    is Err(Journal(@sqlite.Physical(_))),
  )
  db.begin_immediate().unwrap()
  check_native_local_original_signing_use_in_transaction(
    db, grant, original, scope, 101L,
  ).unwrap()
  assert_true(
    db.read("credential-clock-v1", "host-lower-bound").unwrap().body !=
    clock.body,
  )
  db.rollback().unwrap()
  assert_eq(
    db.read("credential-clock-v1", "host-lower-bound").unwrap().body,
    clock.body,
  )
  db.begin_immediate().unwrap()
  check_native_local_original_signing_use_in_transaction(
    db, grant, original, scope, 101L,
  ).unwrap()
  db.commit().unwrap()
  let advanced = db.read("credential-clock-v1", "host-lower-bound").unwrap()
  assert_true(advanced.body != clock.body)
  db.begin_immediate().unwrap()
  check_native_local_original_signing_use_in_transaction(
    db, grant, original, scope, 101L,
  ).unwrap()
  db.commit().unwrap()
  assert_eq(
    db.read("credential-clock-v1", "host-lower-bound").unwrap().body,
    advanced.body,
  )
  assert_eq(
    db.read("credential-clock-v1", "host-lower-bound").unwrap().revision,
    advanced.revision,
  )
  assert_eq(
    db.read(use_scope(cid), scope.attempt_id).unwrap().body,
    use_row.body,
  )
  assert_eq(
    db.read(use_scope(cid), scope.attempt_id).unwrap().revision,
    use_row.revision,
  )
  assert_eq(@credential.local_signing_credential_grant_json(grant), grant_body)
  assert_eq(
    db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
    Some(1L),
  )
  assert_eq(
    db.lookup_claim_ordinal(use_scope(cid), "replacement").unwrap(),
    None,
  )
  assert_true(
    db.read(outcome_scope(cid), scope.attempt_id) is Err(@sqlite.NotFound),
  )
  db.fence_transactions()
  assert_true(
    check_native_local_original_signing_use_in_transaction(
      db, grant, original, scope, 102L,
    )
    is Err(_),
  )
  assert_eq(
    db.read("credential-clock-v1", "host-lower-bound").unwrap().body,
    advanced.body,
  )
  db.close_checked().unwrap()
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "original signing current check refuses expired revoked foreign and missing originals without repair" {
  for variant in 0..<8 {
    let (library, db, _, grant) = original_signing_claim_fixture(
      "signing-current-refuse-" + variant.to_string(),
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    let cid = @credential.local_signing_credential_grant_cid(grant)
    db.begin_immediate().unwrap()
    let original = original_signing_claim_begin(db, grant, 100L).unwrap()
    db.commit().unwrap()
    let use_row = db.read(use_scope(cid), scope.attempt_id).unwrap()
    let clock = db.read("credential-clock-v1", "host-lower-bound").unwrap()
    if variant == 1 || variant == 5 {
      db
      .insert(
        revocation_scope(),
        cid,
        if variant == 1 {
          @utf8.encode(cid)
        } else {
          b"malformed"
        },
      )
      .unwrap()
      |> ignore
    }
    if variant == 7 {
      db.begin_immediate().unwrap()
      db
      .remove_exact(
        use_scope(cid),
        scope.attempt_id,
        use_row.revision,
        use_row.body,
      )
      .unwrap()
      db.commit().unwrap()
    }
    let candidate = if variant == 6 {
      @credential.prepare_local_signing_credential_use(
        grant,
        scope.attempt_id,
        101L,
        1,
        false,
        scope,
      ).unwrap()
    } else {
      original
    }
    db.begin_immediate().unwrap()
    let checked = check_native_local_original_signing_use_in_transaction(
      db,
      grant,
      candidate,
      if variant == 2 {
        { ..scope, preimage: "sha256:" + "f".repeat(64), }
      } else {
        scope
      },
      if variant == 0 {
        10000L
      } else if variant == 3 {
        -1L
      } else if variant == 4 {
        99L
      } else {
        101L
      },
    )
    match variant {
      0 | 1 | 2 => assert_true(checked is Err(Credential(_)))
      3 | 4 => assert_true(checked is Err(TrustedClockRollback))
      5 | 6 => assert_true(checked is Err(Journal(@sqlite.Collision)))
      _ => assert_true(checked is Err(Journal(@sqlite.NotFound)))
    }
    db.rollback().unwrap()
    assert_eq(
      db.read("credential-clock-v1", "host-lower-bound").unwrap().body,
      clock.body,
    )
    assert_eq(
      db.read("credential-clock-v1", "host-lower-bound").unwrap().revision,
      clock.revision,
    )
    if variant == 7 {
      assert_true(
        db.read(use_scope(cid), scope.attempt_id) is Err(@sqlite.NotFound),
      )
    } else {
      assert_eq(
        db.read(use_scope(cid), scope.attempt_id).unwrap().body,
        use_row.body,
      )
    }
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
      Some(1L),
    )
    assert_eq(
      db.lookup_claim_ordinal(use_scope(cid), "replacement").unwrap(),
      None,
    )
    assert_true(
      db.read(outcome_scope(cid), scope.attempt_id) is Err(@sqlite.NotFound),
    )
    db.close_checked().unwrap()
    assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
  }
}

///|
test "succeeded signing history stays read only while expired or revoked signature return is refused" {
  for revoked in [false, true] {
    let (library, db, path, grant) = original_signing_claim_fixture(
      if revoked {
        "signing-current-succeeded-revoked"
      } else {
        "signing-current-succeeded-expired"
      },
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    let cid = @credential.local_signing_credential_grant_cid(grant)
    db.begin_immediate().unwrap()
    let original = original_signing_claim_begin(db, grant, 100L).unwrap()
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      original,
      Succeeded,
    ).unwrap()
    |> ignore
    db.commit().unwrap()
    let clock = db.read("credential-clock-v1", "host-lower-bound").unwrap()
    let use_row = db.read(use_scope(cid), scope.attempt_id).unwrap()
    let outcome = db.read(outcome_scope(cid), scope.attempt_id).unwrap()
    if revoked {
      db.insert(revocation_scope(), cid, @utf8.encode(cid)).unwrap() |> ignore
    }
    db.close_checked().unwrap()
    let restored = library.open_existing_database(path, 8192L).unwrap()
    assert_true(
      prepare_native_local_original_signing_history_candidate(restored, grant)
      .unwrap()
      .observed_outcome()
      is Succeeded,
    )
    assert_eq(
      restored.read("credential-clock-v1", "host-lower-bound").unwrap().body,
      clock.body,
    )
    restored.begin_immediate().unwrap()
    assert_true(
      check_native_local_original_signing_use_in_transaction(
        restored,
        grant,
        original,
        scope,
        if revoked {
          101L
        } else {
          10000L
        },
      )
      is Err(Credential(_)),
    )
    restored.rollback().unwrap()
    assert_true(
      prepare_native_local_original_signing_history_candidate(restored, grant)
      .unwrap()
      .observed_outcome()
      is Succeeded,
    )
    assert_eq(
      restored.read(outcome_scope(cid), scope.attempt_id).unwrap().body,
      outcome.body,
    )
    assert_eq(
      restored.read(use_scope(cid), scope.attempt_id).unwrap().body,
      use_row.body,
    )
    assert_eq(
      restored.read("credential-clock-v1", "host-lower-bound").unwrap().body,
      clock.body,
    )
    assert_eq(
      restored.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
      Some(1L),
    )
    restored.close_checked().unwrap()
    assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
  }
}
