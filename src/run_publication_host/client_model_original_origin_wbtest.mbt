///|
fn client_original_origin_test_wire(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout,
) -> String {
  // This caller fixture connects ACTUAL checked originals. It is not the
  // independent bytes/CID vector or a physical Store acknowledgement.
  let identity = prepared_client_identity(plan.owner)
  let fields = [
    ("barrier_cid", plan.barrier_cid),
    (
      "execution_context_cid",
      @publication.run_publication_execution_context(compiled.admission),
    ),
    (
      "host_policy_cid",
      @publication.run_publication_host_policy(compiled.admission),
    ),
    ("layout_artifact_cid", layout.layout_artifact_cid),
    ("parameter_values_cid", identity.parameter_values_cid),
    (
      "prepared_invocation_cid",
      @publication.run_evidence_value_identity(
        @publication.run_publication_prepared(compiled.admission),
      ),
    ),
    ("program_definition_cid", identity.program_definition_cid),
    (
      "response_profile_cid",
      @environment.model_response_profile_identity(layout.response_profile),
    ),
    (
      "run_definition_cid",
      @publication.publication_contract_identity(definition),
    ),
    ("run_id", "state-original"),
    ("runtime_artifact_cid", layout.runtime_artifact_cid),
    ("storage_binding_cid", "sha256:" + "b".repeat(64)),
  ]
  let origin = fields
    .map(pair => "\"" + pair.0 + "\":\"" + pair.1 + "\"")
    .join(",")
  let state = "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  "{\"cut\":null,\"origin\":{" +
  origin +
  "},\"resource_phase\":\"preparation_base\",\"resource_state\":" +
  state +
  ",\"resource_state_cid\":\"sha256:7ed6db2394d7eaa87d65b022a6bc78f722efaf7a0293115de52c09a89893aae9\",\"version\":\"actql-model-original-resource-state/0.1\"}"
}

///|
test "original checked origin binds all eleven getters without changing original resources" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let layout = client_node_layout_test_declaration(plan)
  let wire = client_original_origin_test_wire(
    compiled, definition, plan, layout,
  )
  let document = @publication.read_model_original_resource_document(
    wire, 10000, 1000, 16,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let check = fn(value) {
    check_client_model_original_checked_origin(
      scope,
      compiled,
      definition,
      plan,
      value,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
  }
  assert_true(check(document) is Ok(_))
  for
    field in [
      "run_id", "run_definition_cid", "prepared_invocation_cid", "host_policy_cid",
      "execution_context_cid", "program_definition_cid", "parameter_values_cid",
      "barrier_cid", "runtime_artifact_cid", "layout_artifact_cid", "response_profile_cid",
    ] {
    let old = @publication.model_original_resource_origin_field(document, field).unwrap()
    let changed = wire.replace(
      old="\"" + field + "\":\"" + old + "\"",
      new="\"" +
        field +
        "\":\"" +
        (if field == "run_id" {
          "other-run"
        } else {
          "sha256:" + "0".repeat(64)
        }) +
        "\"",
    )
    let value = @publication.read_model_original_resource_document(
      changed, 10000, 1000, 16,
    ).unwrap()
    assert_true(check(value) is Err(OriginMismatch(actual)) && actual == field)
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  // Storage is deliberately NOT authenticated by this partial guard. A
  // matching/readable string cannot issue a Store/current/resource/send grant.
  let changed = wire.replace(
    old="\"storage_binding_cid\":\"sha256:" + "b".repeat(64) + "\"",
    new="\"storage_binding_cid\":\"sha256:" + "c".repeat(64) + "\"",
  )
  assert_true(
    check(
      @publication.read_model_original_resource_document(
        changed, 10000, 1000, 16,
      ).unwrap(),
    )
    is Ok(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original checked origin rejects foreign Run and selected installation" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let layout = client_node_layout_test_declaration(plan)
  let installation = client_node_layout_test_installation()
  let document = @publication.read_model_original_resource_document(
    client_original_origin_test_wire(compiled, definition, plan, layout),
    10000,
    1000,
    16,
  ).unwrap()
  let (_, other_definition, other_plan) = client_model_read_test_run(
    "other-run",
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    check_client_model_original_checked_origin(
      scope,
      compiled,
      other_definition,
      plan,
      document,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(ForeignRun),
  )
  assert_true(
    check_client_model_original_checked_origin(
      scope,
      compiled,
      definition,
      other_plan,
      document,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(ForeignRun),
  )
  assert_true(
    check_client_model_original_checked_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      None,
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Layout(Unavailable)),
  )
  assert_true(
    check_client_model_original_checked_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      { ..installation, builder_revision: "2", },
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Layout(_)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original checked origin closing custody refuses without returning pending capacity" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let layout = client_node_layout_test_declaration(plan)
  let document = @publication.read_model_original_resource_document(
    client_original_origin_test_wire(compiled, definition, plan, layout),
    10000,
    1000,
    16,
  ).unwrap()
  // Issuing a child does not revoke an original identity; stopping final
  // inventory does. Neither condition is a stable current-cut certificate.
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  assert_true(
    check_client_model_original_checked_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Ok(_),
  )
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, false).unwrap(),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    check_client_model_original_checked_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Unavailable),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(before.reserved_retention_bytes, 10L)
  assert_true(
    settle_client_model_read_checked(read, compiled, definition, plan, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  settle_client_model_read_checked(read, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    check_client_model_original_checked_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Unavailable),
  )
}
