///|
test "saved Run plan reads first-admission bytes across reopen without starting or changing the Run" {
  let name = "saved-plan-reopen"
  let host = policy_host_fixture(name)
  let crypto = epoch_test_crypto()
  let (_, request, definition) = original_selection_fixture(
    host, "saved-plan-nonce", "saved-plan-run",
  )
  let journal = host.run_journal().unwrap()
  let before = journal.retained(request).unwrap().unwrap()
  let plan = host
    .lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "saved-plan-run",
    )
    .unwrap()
  assert_eq(
    @publication.publication_contract_identity(plan.original().definition()),
    @publication.publication_contract_identity(definition),
  )
  assert_true(plan.wire().contains("\"observation\":\"static\""))
  let after = journal.retained(request).unwrap().unwrap()
  assert_eq(run_record_body(before).unwrap(), run_record_body(after).unwrap())
  assert_eq(before.revision, after.revision)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  host.close().unwrap()
  let restored = policy_host_fixture(name, existing=true)
  let reopened = restored
    .lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "saved-plan-run",
    )
    .unwrap()
  assert_eq(reopened.wire(), plan.wire())
  let retained = restored
    .run_journal()
    .unwrap()
    .retained(request)
    .unwrap()
    .unwrap()
  assert_eq(
    retained.run_observation_originals,
    before.run_observation_originals,
  )
  assert_eq(retained.revision, before.revision)
  restored.close().unwrap()
}

///|
test "saved Run plan missing legacy evidence stays unavailable without repair or dispatch" {
  let host = policy_host_fixture("saved-plan-legacy")
  let crypto = epoch_test_crypto()
  let (_, request, _) = original_selection_fixture(
    host,
    "legacy-plan-nonce",
    "legacy-plan-run",
    retain_plan=false,
  )
  let journal = host.run_journal().unwrap()
  let before = journal.retained(request).unwrap().unwrap()
  assert_true(
    host.lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "legacy-plan-run",
    )
    is Err(Unavailable),
  )
  assert_true(
    host.lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "legacy-plan-nonce",
    )
    is Err(Unavailable),
  )
  let after = journal.retained(request).unwrap().unwrap()
  assert_eq(run_record_body(after).unwrap(), run_record_body(before).unwrap())
  assert_eq(after.run_observation_originals, None)
  assert_eq(after.revision, before.revision)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  host.close().unwrap()
}

///|
test "saved Run plan requires actual current RunRead and refuses a retired Host" {
  let body = @utf8.decode(policy_account_original).replace(
    old="[\"read\",\"submit\"]",
    new="[\"submit\"]",
  )
  let host = policy_host_fixture(
    "saved-plan-denied",
    account_body=@utf8.encode(body),
  )
  let crypto = epoch_test_crypto()
  original_selection_fixture(host, "denied-plan-nonce", "denied-plan-run")
  |> ignore
  assert_true(
    host.lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "denied-plan-run",
    )
    is Err(Journal(AuthorizationDenied)),
  )
  host.close().unwrap()
  assert_true(
    host.lookup_submitted_run_plan_by_id(
      crypto, "operator", "cli", "denied-plan-run",
    )
    is Err(Journal(AuthorizationDenied)),
  )
}

///|
test "saved Run plan capture rejects an equal foreign preparation and changed retained map" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "saved-plan-capture",
  )
  let (_, preparation, _, compiled, definition) = submitted_run_test_input(
    reference, "first-plan",
  )
  let (
    other_intent,
    other_preparation,
    other_request,
    other_compiled,
    other_definition,
  ) = submitted_run_test_input(reference, "other-plan")
  guard preparation.preparation is Computation(prepared) &&
    other_preparation.preparation is Computation(other) else {
    fail("expected checked computations")
  }
  assert_true(
    capture_native_run_plan_original(other, compiled, definition)
    is Err(ForeignRun),
  )
  let ticket = capture_native_run_plan_original(prepared, compiled, definition).unwrap()
  let observation = capture_native_run_observation_originals(
    compiled, definition,
  ).unwrap()
  let held = captured_native_run_stored_observation(
    ticket,
    observation,
    definition,
    ticket.program_cid,
  ).unwrap()
  assert_true(held.matches(held.wire, definition, Some(ticket.program_cid)))
  assert_false(
    held.matches(held.wire + " ", definition, Some(ticket.program_cid)),
  )
  assert_true(
    captured_native_run_stored_observation(
      ticket,
      observation,
      definition,
      "sha256:" + "0".repeat(64),
    )
    is Err(ForeignRun),
  )
  let (_, _, changed_compiled, changed_definition) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    "changed-admission",
    scope="sha256:" + "b".repeat(64),
  )
  assert_true(
    captured_native_run_stored_observation(
      ticket,
      capture_native_run_observation_originals(
        changed_compiled, changed_definition,
      ).unwrap(),
      definition,
      ticket.program_cid,
    )
    is Err(ForeignRun),
  )
  // Both Runs use the same compiled Program. The first-admission ticket must
  // still retain its exact Run definition and original admission evidence.
  assert_eq(
    @publication.publication_contract_identity(
      @host.client_compiled_run_plan(compiled),
    ),
    @publication.publication_contract_identity(
      @host.client_compiled_run_plan(other_compiled),
    ),
  )
  assert_true(
    journal.accept_original_submitted_run(
      authority,
      reference,
      @host.client_submitted_intent_cid(other_intent),
      other_request,
      other_definition,
      "sha256:" + "a".repeat(64),
      true,
      run_observation_originals=Some(
        capture_native_run_observation_originals(
          other_compiled, other_definition,
        ).unwrap(),
      ),
      run_plan_original=Some(ticket),
    )
    is Err(ForeignRun),
  )
  assert_true(journal.retained(other_request).unwrap() is None)
  let wire = native_run_plan_original_wire(ticket.original).unwrap()
  let restored = read_native_run_plan_original(
    wire,
    definition,
    Some(@host.prepared_client_identity(prepared).program_definition_cid),
  ).unwrap()
  assert_eq(restored.view, ticket.original.view)
  let changed = {
    ..ticket.original,
    view: ticket.original.view.replace(
      old="\"logical_map\"",
      new="\"changed_map\"",
    ),
  }
  assert_true(
    read_native_run_plan_original(
      native_run_plan_original_wire(changed).unwrap(),
      definition,
      None,
    )
    is Err(_),
  )
  assert_true(
    read_native_run_plan_original(wire, definition, Some("foreign-program"))
    is Err(ForeignRun),
  )
  database.close_checked().unwrap()
}
