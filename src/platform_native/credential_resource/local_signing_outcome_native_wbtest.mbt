///|
// Actual SQLite outcome/claim custody, never physical signing, permission,
// signature-original storage, Host approval or CLI acceptance.
test "original signing terminal metadata rolls back with its caller and remains immutable after commit" {
  let (library, db, _, grant) = original_signing_claim_fixture(
    "signing-outcome-atomic",
  )
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let cid = @credential.local_signing_credential_grant_cid(grant)
  db.begin_immediate().unwrap()
  let original = original_signing_claim_begin(db, grant, 100L).unwrap()
  db.commit().unwrap()
  let clock = db.read("credential-clock-v1", "host-lower-bound").unwrap()
  let use_row = db.read(use_scope(cid), scope.attempt_id).unwrap()
  db.begin_immediate().unwrap()
  let pending = record_native_local_original_signing_outcome_in_transaction(
    db,
    grant,
    original,
    Succeeded,
  ).unwrap()
  assert_true(pending.observed_outcome() is Succeeded)
  db.rollback().unwrap()
  assert_true(
    db.read(outcome_scope(cid), scope.attempt_id) is Err(@sqlite.NotFound),
  )
  db.begin_immediate().unwrap()
  record_native_local_original_signing_outcome_in_transaction(
    db,
    grant,
    original,
    Succeeded,
  ).unwrap()
  |> ignore
  db.commit().unwrap()
  let terminal = db.read(outcome_scope(cid), scope.attempt_id).unwrap()
  db.begin_immediate().unwrap()
  record_native_local_original_signing_outcome_in_transaction(
    db,
    grant,
    original,
    Succeeded,
  ).unwrap()
  |> ignore
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      original,
      Failed,
    )
    is Err(Journal(@sqlite.Collision)),
  )
  db.rollback().unwrap()
  assert_eq(
    db.read(outcome_scope(cid), scope.attempt_id).unwrap().body,
    terminal.body,
  )
  assert_eq(db.read(outcome_scope(cid), scope.attempt_id).unwrap().revision, 0L)
  assert_eq(
    db.read(use_scope(cid), scope.attempt_id).unwrap().body,
    use_row.body,
  )
  assert_eq(
    db.read("credential-clock-v1", "host-lower-bound").unwrap().body,
    clock.body,
  )
  assert_eq(
    db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
    Some(1L),
  )
  db.close_checked().unwrap()
  // Raw diagnostic Library has no installed component-close ACK contract.
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "original signing terminal metadata rejects unclaimed copied foreign and closed transaction inputs without repair" {
  let (library, db, _, grant) = original_signing_claim_fixture(
    "signing-outcome-inputs",
  )
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let cid = @credential.local_signing_credential_grant_cid(grant)
  let copied = @credential.prepare_local_signing_credential_use(
    grant,
    scope.attempt_id,
    100L,
    0,
    false,
    scope,
  ).unwrap()
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      copied,
      Succeeded,
    )
    is Err(_),
  )
  db.begin_immediate().unwrap()
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      copied,
      Succeeded,
    )
    is Err(Journal(@sqlite.NotFound)),
  )
  db.rollback().unwrap()
  assert_eq(
    db.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
    None,
  )
  db.begin_immediate().unwrap()
  let original = original_signing_claim_begin(db, grant, 100L).unwrap()
  db.commit().unwrap()
  let changed = @credential.prepare_local_signing_credential_use(
    grant,
    scope.attempt_id,
    101L,
    1,
    false,
    scope,
  ).unwrap()
  let other = @credential.prepare_local_signing_credential_grant(
    "foreign-issuer", scope, 10000L, 3,
  ).unwrap()
  db.begin_immediate().unwrap()
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      changed,
      Succeeded,
    )
    is Err(Journal(@sqlite.Collision)),
  )
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      other,
      original,
      Succeeded,
    )
    is Err(_),
  )
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      original,
      Claimed,
    )
    is Err(InvalidConfiguration),
  )
  // Purely reconstructing the same metadata supplies no claim, but can match
  // an actual durable original already admitted above. Eligibility time is
  // deliberately not part of the use body; ordinal and whole body are.
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      copied,
      Succeeded,
    )
    .unwrap()
    .observed_outcome()
    is Succeeded,
  )
  db.rollback().unwrap()
  assert_true(
    db.read(outcome_scope(cid), scope.attempt_id) is Err(@sqlite.NotFound),
  )
  db.fence_transactions()
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      db,
      grant,
      original,
      Succeeded,
    )
    is Err(_),
  )
  assert_true(
    db.read(outcome_scope(cid), scope.attempt_id) is Err(@sqlite.NotFound),
  )
  db.close_checked().unwrap()
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "original signing terminal lost commit return reopens exact history without another signature or claim" {
  let (library, db, path, grant) = original_signing_claim_fixture(
    "signing-outcome-lost-reply",
  )
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let cid = @credential.local_signing_credential_grant_cid(grant)
  db.begin_immediate().unwrap()
  let original = original_signing_claim_begin(db, grant, 100L).unwrap()
  db.commit().unwrap()
  db.begin_immediate().unwrap()
  record_native_local_original_signing_outcome_in_transaction(
    db,
    grant,
    original,
    Unknown,
  ).unwrap()
  |> ignore
  signing_claim_lose_commit_reply(db, 1)
  assert_true(db.commit() is Err(_))
  db.fence_transactions()
  db.close_checked().unwrap()
  let restored = library.open_existing_database(path, 8192L).unwrap()
  let historical = prepare_native_local_original_signing_history_candidate(
    restored, grant,
  ).unwrap()
  assert_true(historical.observed_outcome() is Unknown)
  restored.begin_immediate().unwrap()
  assert_true(
    original_signing_claim_begin(restored, grant, 101L)
    is Err(UseAlreadyClaimed),
  )
  assert_true(
    record_native_local_original_signing_outcome_in_transaction(
      restored,
      grant,
      original,
      Succeeded,
    )
    is Err(Journal(@sqlite.Collision)),
  )
  restored.rollback().unwrap()
  assert_eq(
    restored.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
    Some(1L),
  )
  assert_eq(
    restored.lookup_claim_ordinal(use_scope(cid), "retry").unwrap(),
    None,
  )
  restored.close_checked().unwrap()
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}
