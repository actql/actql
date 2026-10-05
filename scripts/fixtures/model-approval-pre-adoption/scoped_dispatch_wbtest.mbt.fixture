///|
/// Build identity originals from the actual prepared execution, not the
/// independent checkpoint-runtime fixture's different Run and input.
fn dispatch_scope_fixture(
  active : Execution,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  account : @authorization.AdmittedAccountConfiguration,
) -> @publication.BoundModelInvocationScope {
  let plan = active.plan.unwrap()
  let task = @environment.model_execution_task(
    @publication_host.client_infer_plan_graph_execution_contract(plan),
  )
  let set = prepared_model_call_set(active).unwrap()
  let input = @model.prepared_model_call_set_input(set).unwrap()
  let slots = []
  for index in 0..<@model.prepared_model_call_set_count(set).unwrap() {
    slots.push(@model.prepared_model_call_set_slot(set, index).unwrap())
  }
  let context = @publication.run_publication_execution_context(
    @publication_host.client_compiled_run_admission(compiled),
  )
  let cid = "sha256:" + "a".repeat(64)
  let expected : @publication.ModelInvocationBoundary = {
    unit_id: "fixture-infer",
    task_index: @publication_host.client_infer_plan_graph_coordinates(plan).0.to_int64(),
    strategy_revision: 0L,
    inference_barrier_cid: @publication_host.client_infer_plan_graph_barrier_cid(
      plan,
    ),
    account_id: account.account_id(),
    configuration_cid: account.configuration_cid(),
    entry_id: "model-policy",
    principal: "fixture-principal",
    connection: @environment.model_task_connector(task),
    resource: @environment.model_task_identity(task).2,
    context_cid: context,
    installation_revision_cid: cid,
    configuration_contract_cid: cid,
    provider_configuration_cid: cid,
  }
  let provider = @publication.seal_run_evidence_value(
    "model_provider_binding",
    Json::object({
      "version": Json::string("actql-model-provider-binding/0.1"),
      "provider_id": Json::string(expected.connection),
      "installation_revision_cid": Json::string(cid),
      "configuration_contract_cid": Json::string(cid),
      "configuration_cid": Json::string(cid),
    }).stringify(),
    100000,
    10000,
    100,
  ).unwrap()
  let scope = @publication.seal_run_evidence_value(
    "model_invocation_scope",
    Json::object({
      "version": Json::string("actql-model-invocation-scope/0.1"),
      "run_definition_cid": Json::string(
        @publication.publication_contract_identity(definition),
      ),
      "task_index": Json::number(expected.task_index.to_double()),
      "strategy_revision": Json::number(0.0),
      "inference_barrier_cid": Json::string(expected.inference_barrier_cid),
      "input_artifact_cid": Json::string(
        @publication.run_evidence_value_identity(input),
      ),
      "model_call_slot_cids": Json::array(
        slots.map(slot => {
          Json::string(@publication.run_evidence_value_identity(slot))
        }),
      ),
      "provider_binding_cid": Json::string(
        @publication.run_evidence_value_identity(provider),
      ),
      "authorization_context": Json::object({
        "account_id": Json::string(expected.account_id),
        "configuration_cid": Json::string(expected.configuration_cid),
        "entry_id": Json::string(expected.entry_id),
        "principal": Json::string(expected.principal),
        "connection": Json::string(expected.connection),
        "resource": Json::string(expected.resource),
        "operation": Json::string("infer"),
        "boundary": Json::string("activation"),
        "context_cid": Json::string(context),
      }),
    }).stringify(),
    100000,
    10000,
    100,
  ).unwrap()
  @publication.bind_model_invocation_scope(
    @publication_host.client_compiled_run_admission(compiled),
    definition,
    scope,
    provider,
    input,
    slots,
    expected,
  ).unwrap()
}

///|
fn scoped_dispatch_action(
  scope : @publication.BoundModelInvocationScope,
  account : @authorization.AdmittedAccountConfiguration,
) -> @authorization.RuntimeAction {
  let boundary = @publication.model_invocation_scope_boundary(scope)
  let tuple : @authorization.AccessTuple = {
    principal: boundary.principal,
    connection: boundary.connection,
    resource: boundary.resource,
    operation: "infer",
  }
  let matched = match @authorization.evaluate_account(account, tuple) {
    @authorization.Delegate(value) => value
    _ => abort("expected delegated Model fixture")
  }
  let request = @authorization.prepare_decision_request(
    matched,
    configuration_cid=account.configuration_cid(),
    boundary=@authorization.Activation,
    subject_cid=@publication.model_invocation_scope_cid(scope),
    context_cid=boundary.context_cid,
    answering_authorities=["fixture-approver"],
    required_claims=["invocation_scope_approved"],
  ).unwrap()
  @authorization.admit_host_answer(
    request,
    @authorization.Permit(
      { subject: request.subject(), authority: "fixture-approver", },
      ["invocation_scope_approved"],
    ),
  ).unwrap()
}

///|
fn dispatch_fixture_cid(
  fields : Map[String, Json],
  name : String,
) -> String raise {
  let body = Json::object(fields)
  let identity = "sha256:" + @sha.hex(@utf8.encode(fixture_canonical(body)))
  fields[name] = Json::string(identity)
  fixture_canonical(Json::object(fields))
}

///|
/// Authentication and durable readback are explicit test ports here. This
/// exercises real Core grant/dispatch/attempt owners, not public persistence.
fn dispatch_grant_fixture(
  scope : @publication.BoundModelInvocationScope,
  compiled : @publication_host.ClientCompiledRun,
) -> @checkpoint.ModelInvocationGrant raise {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let at = "2026-10-02T00:00:00.000Z"
  let expires = "2098-01-01T00:00:00.000Z"
  let admission = @publication_host.client_compiled_run_admission(compiled)
  let context = @publication.run_publication_execution_context(admission)
  let policy = @publication.run_publication_host_policy(admission)
  let scope_cid = @publication.model_invocation_scope_cid(scope)
  let prepared = @publication.model_invocation_scope_prepared_cid(scope)
  let review = @publication.seal_run_evidence_value(
    "run_review_projection",
    Json::object({
      "version": Json::string("actql-run-review-projection/0.1"),
      "prepared_invocation_cid": Json::string(prepared),
      "execution_context_cid": Json::string(context),
      "host_policy_cid": Json::string(policy),
      "approval_claims": Json::array([Json::string("invocation_scope_approved")]),
      "authoring_context_cid": Json::string(context),
      "redaction_policy_cid": Json::string(policy),
      "sensitivity": Json::string("restricted"),
      "retention_class": Json::string("approval-evidence"),
      "encryption_required": Json::boolean(true),
      "expires_at": Json::string(expires),
      "displayed_scope": Json::object({
        "model_invocation_scope_cid": Json::string(scope_cid),
        "model_call_slot_cids": Json::array(
          @publication.model_invocation_scope_slots(scope).map(id => {
            Json::string(id)
          }),
        ),
      }),
      "displayed_authoring_context": Json::array([]),
    }).stringify(),
    100000,
    10000,
    100,
  ).unwrap()
  let (run_id, definition_cid, unit_id) = @publication.model_invocation_scope_run(
    scope,
  )
  let checkpoint = @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "fixture-model-approval",
      continuation_state_cid: scope_cid,
      subject: @checkpoint.RunUnit(
        run_id~,
        unit_id~,
        run_definition_cid=definition_cid,
      ),
      phase: @checkpoint.Preflight,
      kind: @checkpoint.ModelInvocation,
      required_artifact_cid: scope_cid,
      review_projection_cid: @publication.run_evidence_value_identity(review),
      requirements: [@checkpoint.InvocationScopeApproved],
      reason_code: "model_review_required",
      human_summary: "Review the exact prepared Model calls",
      created_at: at,
      expires_at: expires,
    },
    limits,
  ).unwrap()
  let binding = @checkpoint.bind_model_checkpoint(checkpoint, scope, review).unwrap()
  let proof : Json = Json::object({
    "scheme": Json::string("ed25519-v1"),
    "key_id": Json::string("fixture-reviewer"),
    "signature": Json::string("c2lnbmF0dXJl"),
  })
  let compatibility = dispatch_fixture_cid(
    {
      "version": Json::string("actql-run-scope-approval/0.1"),
      "prepared_invocation_cid": Json::string(prepared),
      "review_projection_cid": Json::string(
        @publication.run_evidence_value_identity(review),
      ),
      "claim": Json::string("invocation_scope_approved"),
      "approver": Json::string("fixture-approver"),
      "approved_at": Json::string(at),
      "expires_at": Json::string(expires),
      "proof": proof,
    },
    "run_scope_approval_cid",
  )
  let evidence = fixture_canonical(
    Json::object({
      "version": Json::string("actql-checkpoint-approval-evidence/0.1"),
      "kind": Json::string("model_invocation"),
      "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
      "review_projection_cid": Json::string(
        @publication.run_evidence_value_identity(review),
      ),
      "compatibility_approval": @json.parse(compatibility),
    }),
  )
  let resolution = dispatch_fixture_cid(
    {
      "version": Json::string("actql-checkpoint-resolution/0.1"),
      "resolution_id": Json::string("fixture-model-resolution"),
      "checkpoint_id": Json::string("fixture-model-approval"),
      "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
      "run_id": Json::string(run_id),
      "run_definition_cid": Json::string(definition_cid),
      "decision": Json::string("approved"),
      "actor": Json::string("fixture-approver"),
      "decided_at": Json::string(at),
      "required_artifact_cid": Json::string(scope_cid),
      "review_projection_cid": Json::string(
        @publication.run_evidence_value_identity(review),
      ),
      "approval_evidence_cid": Json::string(
        "sha256:" + @sha.hex(@utf8.encode(evidence)),
      ),
      "proof": proof,
    },
    "resolution_cid",
  )
  let authentication : @checkpoint.HostAuthentication = {
    key_id: "fixture-reviewer",
    reviewer_id: "fixture-approver",
    expected_authority_scope_cid: scope_cid,
    authority_context_cid: context,
    policy_cid: policy,
    proof_preimage: @checkpoint.resolution_proof_preimage(resolution, limits).unwrap(),
  }
  let admitted = @checkpoint.admit_checkpoint_resolution(
    checkpoint,
    resolution,
    Some(evidence),
    authentication,
    [{ key_id: "fixture-reviewer", reviewer_id: "fixture-approver", }],
    at,
    limits,
    model_binding=binding,
  ).unwrap()
  let verified = @checkpoint.seal_verified_resolution(
    admitted, "fixture-host", "c2lnbmF0dXJl", limits,
  ).unwrap()
  @checkpoint.confirm_model_invocation_grant(
    binding,
    @checkpoint.confirm_checkpoint_persisted(checkpoint, checkpoint.wire).unwrap(),
    verified,
    verified.wire,
    at,
    limits,
  ).unwrap()
}

///|
test "Model scoped dispatch binds the actual prepared inventory rather than the fixed request" {
  let calls = Ref(0)
  let entries = Ref(0)
  let bound_scope : Ref[@publication.BoundModelInvocationScope?] = Ref(None)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    defer_dispatch=true,
    enter_call=Some(entry => {
      let scope = bound_scope.val.unwrap()
      @publication.check_model_invocation_attempt(
        scope,
        @model.model_call_entry_slot(entry),
        @model.model_call_entry_attempt(entry),
        @model.model_call_entry_authority(entry),
        1L,
      ).unwrap()
      entries.val += 1
      true
    }),
  )
  let (compiled, definition) = invocation_fixture_compiled(active)
  let mut waiting = false
  let mut waiting_work = 0L
  for _ in 0..<2000 {
    match advance(active, 1).unwrap() {
      Waiting(work~) => {
        waiting = true
        waiting_work = work
        break
      }
      Continue(_) => ()
      _ => abort("expected prepared input")
    }
  }
  assert_true(waiting)
  let account = evidence_account(@authorization.Delegate)
  let scope = dispatch_scope_fixture(active, compiled, definition, account)
  bound_scope.val = Some(scope)
  let result = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    account,
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    delegated_action=Some(scoped_dispatch_action(scope, account)),
    invocation_scope=Some(scope),
    observe_current=() => Ok((account, "2026-10-02T00:00:00.000Z")),
  )
  assert_true(result is Ok(_))
  let admission = result.unwrap()
  assert_eq(
    @publication_host.client_infer_dispatch_invocation_scope_cid(admission),
    Some(@publication.model_invocation_scope_cid(scope)),
  )
  assert_true(
    @publication_host.check_client_infer_dispatch_current(admission) is Ok(_),
  )
  // The legacy request-bound entry cannot borrow a scope-bound Host answer.
  assert_true(
    @publication_host.issue_client_infer_dispatch_admission(
      compiled,
      definition,
      account,
      "fixture-principal",
      "2026-10-02T00:00:00.000Z",
      delegated_action=Some(scoped_dispatch_action(scope, account)),
      observe_current=() => Ok((account, "2026-10-02T00:00:00.000Z")),
    )
    is Err(@publication_host.Authorization(@authorization.ForeignDecision)),
  )
  assert_eq(calls.val, 0)
  assert_eq(entries.val, 0)
  let grant = dispatch_grant_fixture(scope, compiled)
  assert_true(
    resume_approved_model_call_set(
      active,
      grant,
      admission,
      () => "2100-01-01T00:00:00.000Z",
      () => true,
    )
    is Err(Model(@model.ApprovalUnavailable)),
  )
  assert_eq(calls.val, 0)
  resume_approved_model_call_set(
    active,
    grant,
    admission,
    () => "2026-10-02T00:00:00.000Z",
    () => true,
  ).unwrap()
  assert_true(
    fixture_finish(active, initial_work=waiting_work) is Complete(_, ..),
  )
  assert_eq(calls.val, 1)
  assert_eq(entries.val, 1)
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}
