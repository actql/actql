///|
// Contract-projection cases only: no physical Store or completed Run chain.
fn context_authority_fixture() -> (
  @publication.PublicationContract,
  @publication.PublicationContract,
  NativeRunPublicationIntent,
) {
  let cid = publication_test_cid("context-authority")
  let run = publication_test_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"scope\",\"run_id\":\"run\",\"compiled_plan_cid\":\"" +
    cid +
    "\",\"invocation_template_cid\":\"" +
    cid +
    "\",\"authorization_context_cid\":\"" +
    cid +
    "\",\"input_artifact_set_cid\":\"" +
    cid +
    "\",\"created_at\":\"2026-10-12T00:00:00.000Z\",\"valid_until\":\"2026-10-12T01:00:00.000Z\"}",
  )
  let definition = @publication.result_definition_contract(
    @publication.prepare_result_definition(cid, "answer").unwrap(),
  )
  let intent : NativeRunPublicationIntent = {
    namespace_id: "local",
    authority_scope_cid: publication_test_cid("authority"),
    publication_policy_cid: publication_test_cid("policy"),
    publication_target_cid: publication_test_cid("store"),
    requested_at: "2026-10-12T00:00:00.000Z",
  }
  let request = @publication.issue_publication_request(
    run,
    [definition],
    intent.namespace_id,
    intent.authority_scope_cid,
    intent.publication_policy_cid,
    intent.publication_target_cid,
    intent.requested_at,
    65536,
    4096,
    32,
  ).unwrap()
  (run, request, intent)
}

///|
fn context_authority_index(
  context : @publication.PublicationRequestContext,
  request_cid? : String = context.publication_request_cid,
) -> @publication.PublicationContract {
  let cid = publication_test_cid("stored-reference")
  publication_test_contract(
    "public_index_entry",
    "{\"version\":\"actql-public-index-entry/0.1\",\"namespace_id\":\"local\",\"authority_scope_cid\":\"" +
    context.authority_scope_cid +
    "\",\"run_definition_cid\":\"" +
    context.run_definition_cid +
    "\",\"invocation_cid\":\"" +
    cid +
    "\",\"result_manifest_cid\":\"" +
    cid +
    "\",\"run_receipt_cid\":\"" +
    cid +
    "\",\"captured_run_cid\":\"" +
    cid +
    "\",\"durable_result_binding_cids\":[\"" +
    cid +
    "\"],\"publication_request_cid\":\"" +
    request_cid +
    "\",\"publication_attempt_cid\":\"" +
    cid +
    "\",\"committed_at\":\"2026-10-12T00:00:01.000Z\"}",
  )
}

///|
test "Native context authority receives actual Core request policy target and six facts" {
  let (run, request, intent) = context_authority_fixture()
  let observed : Array[
    (@publication.PublicationRequestContext, NativeRunPublicationAuthorization),
  ] = []
  let context = @publication.project_publication_request_context(request).unwrap()
  let authority = install_native_run_publication_context_authority(_ => true, (
    actual,
    fact,
  ) => {
    observed.push((actual, fact))
    true
  })
  authorize_native_publication_request(
    authority,
    intent,
    run,
    request,
    "request",
    None,
  ).unwrap()
  let index = context_authority_index(context)
  for stage in ["commit", "return_committed"] {
    authorize_native_publication_request(
      authority,
      intent,
      run,
      request,
      stage,
      Some(index),
    ).unwrap()
  }
  assert_eq(observed.length(), 3)
  for (actual, fact) in observed {
    assert_eq(actual, context)
    assert_eq(actual.publication_policy_cid, publication_test_cid("policy"))
    assert_eq(actual.publication_target_cid, publication_test_cid("store"))
    assert_eq(
      fact.publication_request_cid,
      @publication.publication_contract_identity(request),
    )
  }
}

///|
test "Native context authority refuses foreign original selectors before callback" {
  let (run, request, intent) = context_authority_fixture()
  let calls = Ref(0)
  let authority = install_native_run_publication_context_authority(
    _ => {
      calls.val += 1
      true
    },
    (_, _) => {
      calls.val += 1
      true
    },
  )
  let other = publication_test_cid("foreign")
  for
    changed in [
      { ..intent, namespace_id: "foreign", },
      { ..intent, authority_scope_cid: other, },
      { ..intent, publication_policy_cid: other, },
      { ..intent, publication_target_cid: other, },
    ] {
    assert_true(
      authorize_native_publication_request(
        authority,
        changed,
        run,
        request,
        "request",
        None,
      )
      is Err(AccessDenied),
    )
  }
  let context = @publication.project_publication_request_context(request).unwrap()
  let foreign = context_authority_index(context, request_cid=other)
  assert_true(
    authorize_native_publication_request(
      authority,
      intent,
      run,
      request,
      "return_committed",
      Some(foreign),
    )
    is Err(AccessDenied),
  )
  assert_true(
    authorize_native_publication_request(
      authority,
      intent,
      run,
      request,
      "commit",
      None,
    )
    is Err(InvalidConfiguration),
  )
  assert_true(
    authorize_native_publication_request(
      authority,
      intent,
      run,
      request,
      "request",
      Some(foreign),
    )
    is Err(InvalidConfiguration),
  )
  assert_eq(calls.val, 0)
}

///|
test "Native context authority denial and revocation do not become a commit acknowledgement" {
  let (run, request, intent) = context_authority_fixture()
  let current = Ref(true)
  let calls = Ref(0)
  let authority = install_native_run_publication_context_authority(
    _ => {
      current.val = false
      true
    },
    (_, _) => {
      calls.val += 1
      current.val
    },
  )
  assert_true(
    authorize_native_publication_request(
      authority,
      intent,
      run,
      request,
      "request",
      None,
    )
    is Err(AccessDenied),
  )
  assert_eq(calls.val, 1)
  let denied = install_native_run_publication_context_authority(_ => false, (
    _,
    _,
  ) => {
    calls.val += 1
    true
  })
  assert_true(
    authorize_native_publication_request(
      denied,
      intent,
      run,
      request,
      "request",
      None,
    )
    is Err(AccessDenied),
  )
  assert_eq(calls.val, 1)
}
