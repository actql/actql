///|
let environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
let program : String =
  #|{"version":"actql/0.1","id":"python.local.structured","stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"}],"results":{"rows":{"from":"data","fields":["n"]}}},{"id":"compute","inputs":{"seed":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"derive":{"value":"n + 1"},"as":"derived"},{"select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"rows"}}}}

///|
fn environment() -> @checked.CheckEnvironment {
  @host.admit_client_check_environment(
    environment_wire,
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn context_cid() -> String {
  "sha256:" + "a".repeat(64)
}

///|
fn tuple() -> @authorization.AccessTuple {
  {
    principal: "local-user",
    connection: "python.local",
    resource: "runs",
    operation: "submit",
  }
}

///|
fn account(
  outcome : @authorization.ConfiguredOutcome,
) -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration({
    account_id: "local-account",
    entries: [
      {
        entry_id: "local-submission",
        outcome,
        scope: {
          principal: All,
          connection: AnyOf(["python.local"]),
          resource: AnyOf(["runs"]),
          operation: AnyOf(["submit"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
}

///|
fn prepared(input : @input.LocalInput) -> @input.LocalPreparedInput {
  let environment = environment()
  @input.prepare_local_input_material(
    input,
    environment,
    None,
    Some(
      @input.bind_local_input_context(environment, [], "python.local").unwrap(),
    ),
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn permit(
  input : @input.LocalPreparedInput,
  current : @authorization.AdmittedAccountConfiguration,
) -> @authorization.DispatchAuthorization {
  @authorization.bind_dispatch_authorization(
    current,
    tuple(),
    Activation,
    @host.prepared_client_identity(@input.local_prepared_program(input)).program_definition_cid,
    context_cid(),
  ).unwrap()
}

///|
fn plan(input : @input.LocalPreparedInput, id : String) -> LocalRunPlan {
  let current = account(Allow)
  prepare_source_free_local_run(
    input,
    "sha256:" + "b".repeat(64),
    "original-submission",
    permit(input, current),
    current,
    tuple(),
    context_cid(),
    "sha256:" + "c".repeat(64),
    "local",
    id,
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
}

///|
test "structured and AQL materials restore the original admitted Run and request" {
  let text = "/*😀*/\r\nDATA seed = SELECT 1 AS n; FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer"
  for
    (original, id) in [
      (@input.Program(program), "structured-run"),
      (@input.Aql(text), "aql-run"),
    ] {
    let input = prepared(original)
    let plan = plan(input, id)
    let definition_cid = @publication.publication_contract_identity(
      plan.definition,
    )
    let wire = export_local_run_materials(
      plan,
      environment(),
      environment_wire,
      None,
    ).unwrap()
    let restored = restore_local_run_materials(wire, definition_cid).unwrap()
    assert_eq(
      @publication.publication_contract_identity(restored.run_definition),
      definition_cid,
    )
    assert_eq(
      @host.prepared_client_identity(restored.prepared),
      @host.prepared_client_identity(@input.local_prepared_program(input)),
    )
    assert_eq(
      @host.client_task_compilation_result_names(restored.compilation),
      ["answer"],
    )
    let request_wire = @host.client_request_identity_record_wire(plan.request).unwrap()
    let retained = @host.admit_client_request_identity_record_wire(request_wire).unwrap()
    assert_eq(
      @host.client_request_identity_relation(plan.request, retained),
      @host.SameRequest,
    )
    let current = account(Allow)
    assert_true(
      prepare_local_run_start(
        plan,
        retained,
        definition_cid,
        false,
        permit(input, current),
        current,
        tuple(),
        context_cid(),
      )
      is Ok(@host.ReserveDispatch),
    )
    assert_true(
      prepare_local_run_start(
        plan,
        retained,
        definition_cid,
        true,
        permit(input, current),
        current,
        tuple(),
        context_cid(),
      )
      is Ok(@host.ReconcileReservedDispatch),
    )
    match @input.local_prepared_original(input) {
      Aql(original) => assert_eq(original, text)
      Program(original) => assert_eq(original, program)
    }
  }
}

///|
test "saved materials cannot substitute another Run or checked Program" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "original-run")
  let foreign = plan(input, "other-run")
  let wire = export_local_run_materials(
    original,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  assert_true(
    restore_local_run_materials(
      wire,
      @publication.publication_contract_identity(foreign.definition),
    )
    is Err(Materials(_)),
  )
  let changed = wire.replace(old="original-run", new="changed-run")
  assert_true(
    restore_local_run_materials(
      changed,
      @publication.publication_contract_identity(original.definition),
    )
    is Err(Materials(_)),
  )
}

///|
test "current authorization cannot migrate from another subject or retained configuration" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "original-run")
  let current = account(Allow)
  let allowed = permit(input, current)
  let definition_cid = @publication.publication_contract_identity(
    original.definition,
  )
  assert_true(
    prepare_local_run_start(
      original,
      original.request,
      definition_cid,
      false,
      allowed,
      account(Deny),
      tuple(),
      context_cid(),
    )
    is Err(Start(AuthorizationDenied)),
  )
  let foreign_subject = @authorization.bind_dispatch_authorization(
    current,
    tuple(),
    Activation,
    "sha256:" + "d".repeat(64),
    context_cid(),
  ).unwrap()
  assert_true(
    prepare_source_free_local_run(
      input,
      "sha256:" + "b".repeat(64),
      "original-submission",
      foreign_subject,
      current,
      tuple(),
      context_cid(),
      "sha256:" + "c".repeat(64),
      "local",
      "run",
      "2026-10-10T00:00:00.000Z",
      "2099-01-01T00:00:00.000Z",
    )
    is Err(AuthorizationMismatch),
  )
  let changed_context = "sha256:" + "e".repeat(64)
  let changed_permit = @authorization.bind_dispatch_authorization(
    current,
    tuple(),
    Activation,
    @host.prepared_client_identity(@input.local_prepared_program(input)).program_definition_cid,
    changed_context,
  ).unwrap()
  assert_true(
    prepare_local_run_start(
      original,
      original.request,
      definition_cid,
      false,
      changed_permit,
      current,
      tuple(),
      changed_context,
    )
    is Err(Start(AuthorizationDenied)),
  )
}

///|
test "physical start needs durable unstarted proof and cannot override cancellation" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "original-run")
  let current = account(Allow)
  let allowed = permit(input, current)
  let definition_cid = @publication.publication_contract_identity(
    original.definition,
  )
  for
    (reserved, unstarted, cancelled, failed, expected) in [
      (false, true, false, false, false),
      (true, false, false, false, false),
      (true, true, true, false, false),
      (true, true, false, true, false),
      (true, true, false, false, true),
    ] {
    assert_eq(
      prepare_local_run_physical_start(
        original,
        original.request,
        definition_cid,
        reserved,
        unstarted,
        cancelled,
        failed,
        allowed,
        current,
        tuple(),
        context_cid(),
      ).unwrap(),
      expected,
    )
  }
}
