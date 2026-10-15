///|
// Real disposable SQLite records only; no signer, private key or current Allow.
fn operation_history_retain_original(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  use_id : String,
) -> @credential.LocalSigningCredentialUse {
  let cid = @credential.local_signing_credential_grant_cid(grant)
  let ordinal = database.claim_ordinal(use_scope(cid), use_id, 2L).unwrap()
  signing_history_fixture_store_use(database, grant, use_id, ordinal.to_int())
}

///|
test "original Signing operation reads its fixed use and terminal metadata without a new claim" {
  for outcome in ["claimed", "unknown", "failed", "succeeded"] {
    let (_, database, _, grant) = signing_history_fixture(
      "operation-history-" + outcome,
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    let cid = @credential.local_signing_credential_grant_cid(grant)
    let original = operation_history_retain_original(
      database,
      grant,
      scope.attempt_id,
    )
    if outcome != "claimed" {
      database
      .insert(
        outcome_scope(cid),
        scope.attempt_id,
        @utf8.encode(outcome + "\n"),
      )
      .unwrap()
      |> ignore
    }
    let before = database.read(use_scope(cid), scope.attempt_id).unwrap()
    let read = prepare_native_local_original_signing_history_candidate(
      database, grant,
    ).unwrap()
    assert_eq(read.original_use(), original)
    let expected = match outcome {
      "claimed" => NativeLocalSigningHistoryOutcome::Claimed
      "unknown" => NativeLocalSigningHistoryOutcome::Unknown
      "failed" => NativeLocalSigningHistoryOutcome::Failed
      _ => NativeLocalSigningHistoryOutcome::Succeeded
    }
    assert_eq(read.observed_outcome(), expected)
    let after = database.read(use_scope(cid), scope.attempt_id).unwrap()
    assert_eq(after.revision, before.revision)
    assert_eq(after.body, before.body)
    assert_eq(
      database.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
      Some(1L),
    )
    database.close_checked().unwrap()
  }
}

///|
test "original Signing operation rejects extra legacy use or orphan outcome while generic history stays valid" {
  for extra in ["use", "outcome"] {
    let (_, database, _, grant) = signing_history_fixture(
      "operation-extra-" + extra,
    )
    let scope = @credential.local_signing_credential_grant_scope(grant)
    let cid = @credential.local_signing_credential_grant_cid(grant)
    operation_history_retain_original(database, grant, scope.attempt_id)
    |> ignore
    if extra == "use" {
      operation_history_retain_original(database, grant, "legacy-other")
      |> ignore
    } else {
      database.insert(outcome_scope(cid), "legacy-other", b"unknown\n").unwrap()
      |> ignore
    }
    assert_true(
      prepare_native_local_signing_history_candidate(
        database,
        grant,
        scope.attempt_id,
      )
      is Ok(_),
    )
    assert_true(
      prepare_native_local_original_signing_history_candidate(database, grant)
      is Err(Journal(@sqlite.Collision)),
    )
    assert_true(
      prepare_native_local_signing_history_candidate(
        database,
        grant,
        scope.attempt_id,
      )
      is Ok(_),
    )
    database.close_checked().unwrap()
  }
}

///|
test "original Signing operation never adopts ordinal two from the generic multiuse journal" {
  let (_, database, _, grant) = signing_history_fixture("operation-ordinal-two")
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let cid = @credential.local_signing_credential_grant_cid(grant)
  database.claim_ordinal(use_scope(cid), "legacy-other", 2L).unwrap() |> ignore
  operation_history_retain_original(database, grant, scope.attempt_id) |> ignore
  assert_true(
    prepare_native_local_signing_history_candidate(
      database,
      grant,
      scope.attempt_id,
    )
    is Ok(_),
  )
  assert_true(
    prepare_native_local_original_signing_history_candidate(database, grant)
    is Err(Journal(@sqlite.Collision)),
  )
  assert_eq(
    database.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
    Some(2L),
  )
  database.close_checked().unwrap()
}

///|
test "original Signing operation keeps a missing expected use unavailable instead of selecting another" {
  let (_, database, _, grant) = signing_history_fixture("operation-missing-use")
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let cid = @credential.local_signing_credential_grant_cid(grant)
  operation_history_retain_original(database, grant, "legacy-other") |> ignore
  assert_true(
    prepare_native_local_signing_history_candidate(
      database, grant, "legacy-other",
    )
    is Ok(_),
  )
  assert_true(
    prepare_native_local_original_signing_history_candidate(database, grant)
    is Err(Journal(@sqlite.NotFound)),
  )
  assert_eq(
    database.lookup_claim_ordinal(use_scope(cid), scope.attempt_id).unwrap(),
    None,
  )
  database.close_checked().unwrap()
}
