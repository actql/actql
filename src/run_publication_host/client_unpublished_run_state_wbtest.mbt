///|
// Independent closed unpublished metadata. This is not a physical stop or
// journal ACK; the actual caller must establish those originals separately.
let client_unpublished_state : String =
  #|{"control":{"cancellation_requested":true,"physical_stop":"confirmed","revision":4},"next_action":{"kind":"none"},"result_availability":{"answer":{"observed_at":"2026-10-21T00:00:01.000Z","reason":"not_published","state":"unavailable"}},"result_available":false,"revision":0,"run_id":"saved-manifest-fixture","status":"cancelled","updated_at":"2026-10-21T00:00:01.000Z","version":"actql-run-state/0.1"}

///|
let client_unpublished_envelope : String =
  #|{"manifest":null,"run_definition_cid":"sha256:0a872d347ec29b6eb772d3d8421fe4e0daa6f1f1526d3762349461d374335945","state":"{\"control\":{\"cancellation_requested\":true,\"physical_stop\":\"confirmed\",\"revision\":4},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{\"answer\":{\"observed_at\":\"2026-10-21T00:00:01.000Z\",\"reason\":\"not_published\",\"state\":\"unavailable\"}},\"result_available\":false,\"revision\":0,\"run_id\":\"saved-manifest-fixture\",\"status\":\"cancelled\",\"updated_at\":\"2026-10-21T00:00:01.000Z\",\"version\":\"actql-run-state/0.1\"}"}

///|
test "unpublished saved RunState restores exact no-Manifest metadata" {
  let (definition, _) = client_saved_manifest_fixture()
  let restored = restore_client_run_state_original(
    definition, client_unpublished_envelope,
  ).unwrap()
  assert_eq(restored.state_wire(), client_unpublished_state)
  assert_eq(restored.wire(), client_unpublished_envelope)
}

///|
test "unpublished original refuses foreign published malformed and missing metadata" {
  let (definition, _) = client_saved_manifest_fixture()
  assert_eq(
    @publication.validate_original_unpublished_run_state(
      definition, client_unpublished_state, 65536, 8192, 64,
    ),
    Ok(@publication.Cancelled),
  )
  let original = prepare_client_unpublished_run_state_original(
    definition, client_unpublished_state,
  ).unwrap()
  assert_true(original.original_manifest() is None)
  assert_eq(original.wire(), client_unpublished_envelope)
  for
    wire in [
      client_unpublished_state.replace(
        old="saved-manifest-fixture",
        new="foreign-run",
      ),
      client_unpublished_state.replace(
        old="\"status\":\"cancelled\"",
        new="\"status\":\"succeeded\"",
      ),
      client_unpublished_state.replace(
        old="\"state\":\"unavailable\"",
        new="\"state\":\"available\"",
      ),
      client_unpublished_state.replace(
        old="not_published",
        new="confirmed_present",
      ),
      client_unpublished_state.replace(old="\"revision\":0,", new=""),
      client_unpublished_state.replace(
        old="\"kind\":\"none\"",
        new="\"kind\":\"read_result\"",
      ),
      client_unpublished_state.replace(
        old="{\"control\"",
        new="{\"unknown\":true,\"control\"",
      ),
    ] {
    assert_true(
      prepare_client_unpublished_run_state_original(definition, wire)
      is Err(CustodyLost),
    )
  }
}

///|
fn client_unpublished_snapshot(
  body : Bytes,
  generation : Int64,
) -> ClientSavedSubmissionSnapshot {
  let (definition, _) = client_saved_manifest_fixture()
  let text = @utf8.decode(body) catch {
    _ => abort("Independent original fixture is not UTF-8")
  }
  let rows = saved_snapshot_rows(text)
  for index in 0..<rows.length() {
    let (table, row) = rows[index]
    if table == "client_submitted_intents" {
      rows[index] = (table, { ..row, revision: generation, })
    }
  }
  read_client_saved_submission(
    saved_snapshot_reference(),
    (table, key) => inventory_read(rows, table, key),
    _ => Ok({ ..saved_snapshot_run(), definition, }),
    "custody",
  )
  .unwrap()
  .unwrap()
}

///|
test "unpublished state metadata confirms exact saved successor and keeps terminal immutable" {
  let (definition, _) = client_saved_manifest_fixture()
  let retained = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let admission = retained.run_admission.unwrap()
  let body = client_submitted_intent_journal_row_body(
    client_submission_reference_record_wire(retained.reference),
    retained.intent,
    run_admission=Some(
      (
        admission.0,
        @publication.publication_contract_identity(definition),
        admission.2,
      ),
    ),
    run_state_observation=Some((0L, None)),
  ).unwrap()
  let original = client_unpublished_snapshot(body, 6L)
  let update = prepare_client_unpublished_run_state_update(
    original,
    original.inspection.unwrap().request,
    definition,
    client_unpublished_state,
  ).unwrap()
  let (_, before, after, next) = client_saved_run_state_update_row(update)
  assert_eq((before, after), (6L, 7L))
  assert_true(
    confirm_client_saved_run_state_update(update, original)
    is Err(OriginalUnavailable),
  )
  let saved = client_unpublished_snapshot(next, after)
  assert_eq(
    confirm_client_saved_run_state_update(update, saved).unwrap(),
    client_unpublished_state,
  )
  let saved_run = client_saved_submission_run_row(saved).unwrap()
  let original_run = client_saved_submission_run_row(original).unwrap()
  assert_eq(
    (saved_run.key, saved_run.revision, saved_run.body),
    (original_run.key, original_run.revision, original_run.body),
  )
  let same = prepare_client_unpublished_run_state_update(
    saved,
    saved.inspection.unwrap().request,
    definition,
    client_unpublished_state.replace(old="00:00:01.000Z", new="00:00:02.000Z"),
  ).unwrap()
  assert_eq(
    client_saved_run_state_update_row(same),
    client_saved_run_state_update_row(
      prepare_client_unpublished_run_state_update(
        saved,
        saved.inspection.unwrap().request,
        definition,
        client_unpublished_state,
      ).unwrap(),
    ),
  )
  assert_eq(
    client_saved_run_state_update_candidate_wire(same),
    client_unpublished_state,
  )
  assert_true(
    prepare_client_unpublished_run_state_update(
      saved,
      saved.inspection.unwrap().request,
      definition,
      client_unpublished_state.replace(
        old="\"status\":\"cancelled\"",
        new="\"status\":\"running\"",
      ),
    )
    is Err(ForeignRun),
  )
}

///|
test "dependent Unknown requires the exact selected Entry proof" {
  let (definition, _) = client_saved_manifest_fixture()
  let run_id = @publication.run_definition_run_id(definition).unwrap()
  let unknown = @publication.issue_effect_free_unpublished_run_state_wire(
    run_id,
    "2026-10-21T00:00:01.000Z",
    ["answer"],
    true,
    false,
    65536,
    8192,
    64,
    execution_unknown=true,
  ).unwrap()
  let observation = @publication.prepare_run_state_observation(
    unknown, run_id, 0L, 65536, 8192, 64,
  ).unwrap()
  let state = observation.wire(0L).unwrap()
  let plain = prepare_client_unpublished_run_state_original(definition, state).unwrap()
  assert_eq(
    restore_client_run_state_original(definition, plain.wire())
    .unwrap()
    .state_wire(),
    state,
  )
  let attempt = "sha256:" + "a".repeat(64)
  let digest = "sha256:" + "b".repeat(64)
  let original = prepare_client_dependent_model_unknown_run_state_original(
    definition, state, attempt, digest,
  ).unwrap()
  let retained = admit_client_retained_run_state_original(
    definition,
    original.wire(),
    0L,
    observation.key(),
  ).unwrap()
  assert_true(retained.requires_model_proof())
  assert_true(retained.requires_dependent_model_unknown_proof())
  assert_true(retained.resolve() is Err(CustodyLost))
  assert_true(
    restore_client_run_state_original(definition, original.wire())
    is Err(CustodyLost),
  )
  let bare = decode_client_run_state_original_body(
    definition,
    original.wire(),
    false,
  ).unwrap()
  assert_true(
    bare.resolve(resolve_dependent_model_unknown=Some((_, _) => true))
    is Err(CustodyLost),
  )
  assert_true(
    retained.resolve(
      resolve_dependent_model_unknown=Some((actual_attempt, actual_digest) => {
        (actual_attempt, actual_digest) == (attempt, attempt)
      }),
    )
    is Err(CustodyLost),
  )
  let selected = retained
    .resolve(
      resolve_dependent_model_unknown=Some((actual_attempt, actual_digest) => {
        (actual_attempt, actual_digest) == (attempt, digest)
      }),
    )
    .unwrap()
  assert_eq(selected.state_wire(), state)
  assert_eq(selected.wire(), original.wire())
  assert_true(
    admit_client_retained_run_state_original(
      definition,
      original.wire(),
      0L,
      "foreign-observation",
    )
    is Err(CustodyLost),
  )
  assert_true(
    prepare_client_dependent_model_unknown_run_state_original(
      definition, client_unpublished_state, attempt, digest,
    )
    is Err(CustodyLost),
  )
  assert_true(
    validate_client_historical_run_state_original(definition, original.wire())
    is Err(CustodyLost),
  )
  let partial = original
    .wire()
    .replace(old=",\"model_unknown_entry_digest\":\"" + digest + "\"", new="")
  assert_true(
    restore_client_run_state_original(definition, partial) is Err(CustodyLost),
  )
}
