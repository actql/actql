///|
fn start_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn start_test_definition() -> @publication.PublicationContract {
  @publication.seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\"," +
    "\"scope_id\":\"scope-a\",\"run_id\":\"run-a\"," +
    "\"compiled_plan_cid\":\"" +
    start_test_cid("1") +
    "\",\"invocation_template_cid\":\"" +
    start_test_cid("2") +
    "\",\"authorization_context_cid\":\"" +
    start_test_cid("3") +
    "\",\"input_artifact_set_cid\":\"" +
    start_test_cid("4") +
    "\",\"created_at\":\"2026-09-24T00:00:00.000Z\"," +
    "\"valid_until\":\"2099-01-01T00:00:00.000Z\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
test "Client Run start reserves once and never repeats an uncertain dispatch" {
  let request : ClientRequestIdentity = {
    authority_scope_cid: start_test_cid("a"),
    caller_request_id: "request-a",
    scope: @request_scope.prepare_logical_request_scope(
      start_test_cid("a"),
      "request-a",
      256,
    ).unwrap(),
    intent_fingerprint_cid: start_test_cid("c"),
    program_definition_cid: start_test_cid("d"),
    parameter_values_cid: start_test_cid("e"),
    caller_input_intent_cid: start_test_cid("f"),
  }
  let definition = start_test_definition()
  let run_cid = @publication.publication_contract_identity(definition)
  assert_eq(
    prepare_client_run_start(request, request, definition, run_cid, false, true),
    Ok(ReserveDispatch),
  )
  assert_eq(
    prepare_client_run_start(request, request, definition, run_cid, true, true),
    Ok(ReconcileReservedDispatch),
  )
  assert_eq(
    prepare_client_run_start(
      request, request, definition, run_cid, false, false,
    ),
    Err(AuthorizationDenied),
  )
  assert_eq(
    prepare_client_run_start(
      request,
      { ..request, caller_input_intent_cid: start_test_cid("0"), },
      definition,
      run_cid,
      false,
      true,
    ),
    Err(ChangedIntent),
  )
  assert_eq(
    prepare_client_run_start(
      request,
      { ..request, caller_input_intent_cid: start_test_cid("0"), },
      definition,
      run_cid,
      false,
      false,
    ),
    Err(AuthorizationDenied),
  )
  assert_eq(
    prepare_client_run_start(
      request,
      { ..request, caller_request_id: "request-b", },
      definition,
      run_cid,
      false,
      true,
    ),
    Err(DifferentRequest),
  )
  assert_eq(
    prepare_client_run_start(
      request,
      request,
      definition,
      start_test_cid("9"),
      false,
      true,
    ),
    Err(ForeignRunDefinition),
  )
}

///|
test "Client Run physical start requires exact retained and unstarted evidence" {
  let request : ClientRequestIdentity = {
    authority_scope_cid: start_test_cid("a"),
    caller_request_id: "request-a",
    scope: @request_scope.prepare_logical_request_scope(
      start_test_cid("a"),
      "request-a",
      256,
    ).unwrap(),
    intent_fingerprint_cid: start_test_cid("c"),
    program_definition_cid: start_test_cid("d"),
    parameter_values_cid: start_test_cid("e"),
    caller_input_intent_cid: start_test_cid("f"),
  }
  let definition = start_test_definition()
  let run_cid = @publication.publication_contract_identity(definition)
  assert_eq(
    prepare_client_run_pre_start_failure(
      request, request, definition, run_cid, true, true, true, false,
    ),
    Ok(true),
  )
  for
    flags in [
      (false, true, true, false),
      (true, false, true, false),
      (true, true, false, false),
      (true, true, true, true),
    ] {
    assert_eq(
      prepare_client_run_pre_start_failure(
        request,
        request,
        definition,
        run_cid,
        flags.0,
        flags.1,
        flags.2,
        flags.3,
      ),
      Ok(false),
    )
  }
  assert_eq(
    prepare_client_run_pre_start_failure(
      request,
      { ..request, caller_input_intent_cid: start_test_cid("0"), },
      definition,
      run_cid,
      true,
      true,
      true,
      false,
    ),
    Err(ChangedIntent),
  )
  assert_eq(
    prepare_client_run_pre_start_failure(
      request,
      request,
      definition,
      start_test_cid("0"),
      true,
      true,
      true,
      false,
    ),
    Err(ForeignRunDefinition),
  )
  assert_eq(
    prepare_client_run_physical_start(
      request,
      request,
      definition,
      run_cid,
      true,
      true,
      true,
      pre_start_failure_confirmed=true,
    ),
    Ok(false),
  )
  assert_eq(
    prepare_client_run_physical_start(
      request, request, definition, run_cid, true, true, true,
    ),
    Ok(true),
  )
  assert_eq(
    prepare_client_run_physical_start(
      request, request, definition, run_cid, true, false, true,
    ),
    Ok(false),
  )
  assert_eq(
    prepare_client_run_physical_start(
      request, request, definition, run_cid, false, true, true,
    ),
    Ok(false),
  )
  assert_eq(
    prepare_client_run_physical_start(
      request, request, definition, run_cid, true, true, false,
    ),
    Err(AuthorizationDenied),
  )
  assert_eq(
    prepare_client_run_physical_start(
      request,
      { ..request, caller_input_intent_cid: start_test_cid("0"), },
      definition,
      run_cid,
      true,
      true,
      true,
    ),
    Err(ChangedIntent),
  )
}

///|
test "cancellation keeps exact Run authority and terminal outcome" {
  let definition = start_test_definition()
  let cid = @publication.publication_contract_identity(definition)
  assert_eq(
    prepare_client_run_cancellation(definition, cid, true, false, false),
    Ok(AcceptCancellation),
  )
  assert_eq(
    prepare_client_run_cancellation(definition, cid, true, false, true),
    Ok(AlreadyRequested),
  )
  assert_eq(
    prepare_client_run_cancellation(definition, cid, true, true, true),
    Ok(AlreadyTerminal),
  )
  assert_eq(
    prepare_client_run_cancellation(definition, cid, false, false, false),
    Err(AuthorizationDenied),
  )
  assert_eq(
    prepare_client_run_cancellation(
      definition,
      start_test_cid("0"),
      true,
      false,
      false,
    ),
    Err(ForeignRunDefinition),
  )
}

///|
test "terminal cancellation requires each independent stop fact" {
  let confirmed : ClientRunCancellationFacts = {
    cancellation_requested: true,
    model_fence_required: true,
    model_fenced: true,
    unresolved_model_calls: false,
    unresolved_effects: false,
    reconciliation_required: false,
    publication_committed: false,
    physical_stop_confirmed: true,
    cleanup_confirmed: true,
    revision_unchanged: true,
  }
  assert_true(confirm_client_run_cancellation(confirmed))
  for
    missing in [
      { ..confirmed, cancellation_requested: false, },
      { ..confirmed, model_fenced: false, },
      { ..confirmed, unresolved_model_calls: true, },
      { ..confirmed, unresolved_effects: true, },
      { ..confirmed, reconciliation_required: true, },
      { ..confirmed, publication_committed: true, },
      { ..confirmed, physical_stop_confirmed: false, },
      { ..confirmed, cleanup_confirmed: false, },
      { ..confirmed, revision_unchanged: false, },
    ] {
    assert_false(confirm_client_run_cancellation(missing))
  }
  // A Run without Model work requires no Model-specific fence.
  assert_true(
    confirm_client_run_cancellation({
      ..confirmed,
      model_fence_required: false,
      model_fenced: false,
    }),
  )
}
