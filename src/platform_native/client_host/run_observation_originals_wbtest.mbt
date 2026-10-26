///|
test "original Run evidence commits with first Submission and reopens without recapture" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "observation-first-accept",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "observation-first",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let accepted = journal
    .accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1001.0,
    )
    .unwrap()
  let saved = journal.retained(request).unwrap().unwrap()
  let wire = saved.run_observation_originals.unwrap()
  let original = read_native_run_observation_originals(wire, definition).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(original.prepared()),
    @publication.run_evidence_value_json(
      @host.client_compiled_run_prepared(compiled),
    ),
  )
  assert_eq(
    @publication.run_evidence_value_json(original.authorization()),
    @publication.run_evidence_value_json(
      @host.client_compiled_run_authorization(compiled),
    ),
  )
  assert_false(saved.physical_start_claimed)
  assert_false(saved.dispatch_reserved)
  let repeated = journal
    .accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1001.0,
    )
    .unwrap()
  assert_eq(repeated.revision, accepted.revision)
  assert_eq(
    journal.retained(request).unwrap().unwrap().revision,
    saved.revision,
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database("observation-first-accept")
  let restored = open_native_client_run_journal(reopened, 8)
    .unwrap()
    .retained(request)
    .unwrap()
    .unwrap()
  assert_eq(restored.run_observation_originals, Some(wire))
  assert_false(restored.physical_start_claimed)
  reopened.close_checked().unwrap()
}

///|
test "accepted legacy missing evidence remains missing after same operation acceptance" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "observation-legacy-missing",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "observation-legacy",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let accepted = journal
    .accept_original_submitted_run(
      authority,
      reference,
      @host.client_submitted_intent_cid(intent),
      request,
      definition,
      scope,
      true,
    )
    .unwrap()
  let before = journal.retained(request).unwrap().unwrap()
  assert_eq(before.run_observation_originals, None)
  let repeated = journal
    .accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1001.0,
    )
    .unwrap()
  let after = journal.retained(request).unwrap().unwrap()
  assert_eq(after.run_observation_originals, None)
  assert_eq(after.revision, before.revision)
  assert_eq(repeated.revision, accepted.revision)
  database.close_checked().unwrap()
}

///|
test "original Run evidence admission refuses current denial and orphan backfill" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "observation-current-orphan",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "observation-denied",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, false,
      1001.0,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(journal.retained(request).unwrap() is None)
  guard preparation.preparation is Computation(prepared) else {
    fail("expected original computation fixture")
  }
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1001.0,
    )
    is Err(CustodyLost),
  )
  assert_eq(
    journal.retained(request).unwrap().unwrap().run_observation_originals,
    None,
  )
  database.close_checked().unwrap()
}

///|
fn read_native_run_observation_originals(
  wire : String,
  definition : @publication.PublicationContract,
  program_cid? : String? = None,
) -> Result[@host.ClientRunObservationOriginals, NativeClientRunJournalIssue] {
  read_native_stored_run_observation(wire, definition, program_cid).map(value => {
    value.observation
  })
}
