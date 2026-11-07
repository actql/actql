///|
// Ordinary Program preparation and bounded input execution issue all handles.
// Symbolic installation roots are fixture metadata, not real provider evidence.
fn entry_gate_fixture(
  calls : Ref[Int],
  current : Ref[@authorization.AdmittedAccountConfiguration],
  now : Ref[String],
  egress : Ref[@publication_host.ClientInferEgressObservation?],
  configure? : (Execution) -> Unit = _ => (),
  limits? : Limits = standard_limits(),
  asynchronous? : Bool = false,
  start_original? : (() -> Execution)? = None,
  slots? : Int = 2,
) -> (
  Execution,
  @model.ModelPreparedCallSet,
  @publication_host.ClientInferDispatchAdmission,
  Int64,
) raise {
  let active = match start_original {
    Some(start) => start()
    None => contract_capacity_start(calls, 2, 133072L, limits~, asynchronous~)
  }
  configure(active)
  require_model_call_entry(active).unwrap()
  let contract = @publication_host.client_infer_plan_graph_execution_contract(
    active.plan.unwrap(),
  )
  let egress_result = match active.prepared {
    Some(prepared) =>
      @publication_host.admit_prepared_client_infer_egress(
        prepared,
        2,
        contract,
        () => egress.val,
      )
    None =>
      @publication_host.admit_client_infer_occurrence_egress(
        active.occurrence,
        contract,
        () => egress.val,
      )
  }
  let egress_admission = egress_result.unwrap()
  bind_egress_admission(active, egress_admission).unwrap()
  let (compiled, definition) = match active.run_binding {
    Some(original) => (original.compiled, original.definition)
    None => invocation_fixture_compiled(active)
  }
  let prefix_work = match fixture_finish(active) {
    Waiting(work~) => work
    Failed(Model(issue), ..) => {
      assert_eq(Some(issue), None)
      abort("Model preparation refused before original entry binding")
    }
    Failed(Input(_), ..) => abort("input preparation refused")
    Failed(Capacity(_), ..) => abort("Host capacity preparation refused")
    Failed(IdentityExport(_), ..) => abort("input identity preparation refused")
    Failed(CallScope(_), ..) => abort("original call scope preparation refused")
    Failed(OriginalCapacity(_), ..) =>
      abort("original read capacity preparation refused")
    _ => abort("ordinary preparation must wait for original entry binding")
  }
  let prepared = prepared_call_set(active).unwrap()
  assert_eq(@model.prepared_model_call_count(prepared), Some(slots))
  let artifact = @model.prepared_model_input_artifact(prepared).unwrap()
  let (_, task_cid, _) = @model.prepared_model_identities(prepared).unwrap()
  let root = "sha256:" + "a".repeat(64)
  let provider = @publication.seal_run_evidence_value(
    "model_provider_binding",
    fixture_canonical(
      Json::object({
        "version": Json::string("actql-model-provider-binding/0.1"),
        "provider_id": Json::string("models/fixture"),
        "installation_revision_cid": Json::string(root),
        "configuration_contract_cid": Json::string(root),
        "configuration_cid": Json::string(root),
      }),
    ),
    16384,
    1024,
    20,
  ).unwrap()
  let plan = active.plan.unwrap()
  let boundary : @publication.ModelInvocationBoundary = {
    unit_id: @publication_host.client_infer_call_scope_unit_id(
      active.call_scope.unwrap(),
    ).unwrap(),
    task_index: @publication_host.client_infer_occurrence_coordinates(
      active.occurrence,
    ).0.to_int64(),
    strategy_revision: 0L,
    inference_barrier_cid: @publication_host.client_infer_plan_graph_barrier_cid(
      plan,
    ),
    account_id: "infer-fixture",
    configuration_cid: current.val.configuration_cid(),
    entry_id: "model-policy",
    principal: "fixture-principal",
    connection: "models/fixture",
    resource: task_cid,
    context_cid: root,
    installation_revision_cid: root,
    configuration_contract_cid: root,
    provider_configuration_cid: root,
  }
  let scope = @publication.seal_run_evidence_value(
    "model_invocation_scope",
    fixture_canonical(
      Json::object({
        "version": Json::string("actql-model-invocation-scope/0.1"),
        "run_definition_cid": Json::string(
          @publication.publication_contract_identity(definition),
        ),
        "task_index": Json::number(boundary.task_index.to_double()),
        "strategy_revision": Json::number(0),
        "inference_barrier_cid": Json::string(boundary.inference_barrier_cid),
        "input_artifact_cid": Json::string(
          @publication.run_evidence_value_identity(artifact),
        ),
        "model_call_slot_cids": Json::array(
          Array::makei(slots, slot => {
            Json::string(
              @publication.run_evidence_value_identity(
                @model.prepared_model_call_at(prepared, slot).unwrap(),
              ),
            )
          }),
        ),
        "provider_binding_cid": Json::string(
          @publication.run_evidence_value_identity(provider),
        ),
        "authorization_context": Json::object({
          "account_id": Json::string(boundary.account_id),
          "configuration_cid": Json::string(boundary.configuration_cid),
          "entry_id": Json::string(boundary.entry_id),
          "principal": Json::string(boundary.principal),
          "connection": Json::string(boundary.connection),
          "resource": Json::string(boundary.resource),
          "operation": Json::string("infer"),
          "boundary": Json::string("activation"),
          "context_cid": Json::string(boundary.context_cid),
        }),
      }),
    ),
    16384,
    1024,
    20,
  ).unwrap()
  let bound = bind_model_scope(active, prepared, scope, provider, boundary).unwrap()
  let admission = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    current.val,
    "fixture-principal",
    now.val,
    model_scope=Some(bound),
    observe_current=() => Ok((current.val, now.val)),
  ).unwrap()
  assert_eq(calls.val, 0)
  (active, prepared, admission, prefix_work)
}

///|
test "entry acknowledgement binds the original handle and starts each call once" {
  let calls = Ref(0)
  let current = Ref(evidence_account(@authorization.Allow))
  let now = Ref("2026-10-02T00:00:00.000Z")
  let egress = Ref(Some(egress_fixture_observation()))
  let (active, prepared, admission, prefix_work) = entry_gate_fixture(
    calls, current, now, egress,
  )
  let saved : Array[@model.ModelCallEntryAcknowledgement] = []
  let checks : Array[Bool] = []
  bind_model_dispatch(active, prepared, admission, entry => {
    let acknowledgement = @model.acknowledge_model_call_entry(entry, prepared).unwrap()
    checks.push(
      @model.model_call_entry_acknowledgement_current(acknowledgement, prepared),
    )
    // The same original persistence acknowledgement is idempotent, not a new
    // permission. The execution consumes its single original start gate.
    checks.push(
      physical_equal(
        acknowledgement,
        @model.acknowledge_model_call_entry(entry, prepared).unwrap(),
      ),
    )
    saved.push(acknowledgement)
    true
  }).unwrap()
  let mut work = prefix_work
  for _ in 0..<2 {
    work = match fixture_finish(active, initial_work=work) {
      Settling(_, work~) => work
      _ => abort("each original entry must wait for its settlement")
    }
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
  }
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_eq(saved.length(), 2)
  assert_eq(checks.length(), 4)
  for check in checks {
    assert_true(check)
  }
  for acknowledgement in saved {
    assert_true(
      !@model.model_call_entry_acknowledgement_current(
        acknowledgement, prepared,
      ),
    )
  }
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "entry persistence cannot reuse earlier permission after cancellation revocation or expiry" {
  for variant in ["cancel", "revoke", "egress", "expiry", "false", "unknown"] {
    let calls = Ref(0)
    let current = Ref(evidence_account(@authorization.Allow))
    let now = Ref("2026-10-02T00:00:00.000Z")
    let egress = Ref(Some(egress_fixture_observation()))
    let (active, prepared, admission, prefix_work) = entry_gate_fixture(
      calls, current, now, egress,
    )
    let entries = Ref(0)
    let entry_current = Ref(false)
    let original_attempts : Array[String] = []
    bind_model_dispatch(active, prepared, admission, entry => {
      entries.val += 1
      entry_current.val = @model.model_call_entry_current(entry, prepared)
      let (_, _, attempt, _) = @model.model_call_entry_originals(entry).unwrap()
      original_attempts.push(attempt)
      match variant {
        "cancel" => cancel(active) |> ignore
        "revoke" => current.val = evidence_account(@authorization.Deny)
        "egress" =>
          egress.val = Some({
            ..egress_fixture_observation(),
            region: "changed-region",
          })
        "expiry" => now.val = "2100-01-01T00:00:00.000Z"
        _ => ()
      }
      // The existing synchronous adapter reports both an unsuccessful write
      // and an unconfirmed durable write as false, never as permission to send.
      variant != "false" && variant != "unknown"
    }).unwrap()
    let result = fixture_finish(active, initial_work=prefix_work)
    match variant {
      "cancel" => assert_true(result is Stopped(_))
      "false" | "unknown" =>
        assert_true(result is Failed(Model(@model.CallEntryRefused), ..))
      "egress" => assert_true(result is Failed(Model(@model.Egress(_)), ..))
      _ => assert_true(result is Failed(Model(@model.Authorization(_)), ..))
    }
    assert_eq(entries.val, 1)
    assert_true(entry_current.val)
    assert_eq(calls.val, 0)
    let model = active.model.unwrap()
    if variant == "false" || variant == "unknown" {
      assert_eq(@model.stopped_model_attempt_count(model), Some(0))
    } else {
      // EnteredUnknown was acknowledged before the final check failed. Keep
      // its exact original attempt rather than inventing a successful send.
      assert_eq(@model.stopped_model_attempt_count(model), Some(1))
      assert_eq(@model.stopped_model_attempt_slot(model, 0), Some(0))
      let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
      assert_eq(
        @publication.run_evidence_value_json(
          @model.model_attempt_identity(proof),
        ),
        original_attempts[0],
      )
      if variant != "cancel" {
        assert_true(
          @publication.run_evidence_value_json(
            @model.model_attempt_outcome(proof),
          ).contains("\"category\":\"result_unknown\""),
        )
      }
    }
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    assert_true(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 0)
  }
}
