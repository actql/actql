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
    logical_request_scope_cid: start_test_cid("b"),
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
    logical_request_scope_cid: start_test_cid("b"),
    intent_fingerprint_cid: start_test_cid("c"),
    program_definition_cid: start_test_cid("d"),
    parameter_values_cid: start_test_cid("e"),
    caller_input_intent_cid: start_test_cid("f"),
  }
  let definition = start_test_definition()
  let run_cid = @publication.publication_contract_identity(definition)
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
