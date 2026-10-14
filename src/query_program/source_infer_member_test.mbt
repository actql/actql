///|
// Admit Source and ModelTask bodies in one wire generation. ASCII canonical
// preimages are retained in source-infer-member-catalog-independent.json;
// SHA-256 was computed independently with Python, not common preparation.
fn source_infer_member_environment() -> @check.CheckEnvironment {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:232d374fc64aa44fe8fe5f713807e4f92ede7695c1b89354ac13e4c6779df153","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"payload":{"additional_properties":false,"fields":{"score":{"nullable":true,"type":"number"}},"nullable":true,"type":"object"}},"nullable":false,"type":"object"},"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:82062d0e4efb4df3d93c732e93b6b52038e642d9004d7a5c288509b8feaa4268","output":{"carrier":"relation","data_policy":{"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"payload":{"additional_properties":false,"fields":{"score":{"nullable":true,"type":"number"}},"nullable":true,"type":"object"}},"nullable":false,"type":"object"},"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:c5d9b481b5ab7b396ee6a158246d51505fe58d2b6776d8580c929d79f4947fce","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:82062d0e4efb4df3d93c732e93b6b52038e642d9004d7a5c288509b8feaa4268","output":{"carrier":"relation","data_policy":{"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:c5d9b481b5ab7b396ee6a158246d51505fe58d2b6776d8580c929d79f4947fce",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let tasks = @environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 100,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
  @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=Some(tasks),
  )
}

///|
fn source_infer_member_context(
  environment : @check.CheckEnvironment,
) -> Context raise {
  let prepared = @check.prepare_source_catalog(environment, {
    max_work: 1000000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let base = source_member_context()
  let cid = @check.checking_environment_cid(environment)
  let bound = @frontend.bind_query_context(
    [
      {
        name: [{ value: "objects", quoted: false, }],
        source_ref: "connector://crm/main/r#v",
        environment_cid: cid,
        input: Relation(base.inputs[0]),
      },
    ],
    cid,
    program_id="fixture.query_pair",
    input_schemas=base.input_schemas,
    source_catalog=Some(@check.source_catalog_contracts(prepared)),
    model_tasks=@check.checking_environment_model_tasks(environment),
  ).unwrap()
  // This independent machine control reads the Source in the same Stage.
  // It proves ordinary Source/ModelTask typing, not public capture acceptance.
  // The original raw-object capture refusal remains covered separately.
  { ..bound, captured_stage: None, }
}

///|
fn source_infer_member_control() -> @program.Program {
  // Ordinary Source, DISTINCT, infer and object/property projection. The key
  // is established by DISTINCT, not the ITEM KEY spelling or a Source guess.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.source_infer_control","stages":[{"id":"main","inputs":{"objects":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"from":"objects","select":["id"]},{"distinct":["id"]},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"literal":"urgent"}}},"as":"outcomes"},{"derive":{"assessment":{"object":{"input_key":{"object":{"id":{"field":"id"}}},"outcome":{"field":"outcome"},"value":{"field":"value"}}}}},{"derive":{"risk":{"property":{"name":"risk","value":{"property":{"name":"value","value":{"field":"assessment"}}}}}}},{"select":["risk"],"as":"final"}],"results":{"rows":{"from":"final","fields":["risk"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn source_infer_member_check(
  program : @program.Program,
  environment : @check.CheckEnvironment,
) -> Unit raise {
  match @check.check_parsed(program, environment, None, check_limits()) {
    Checked(checked) => {
      let output = @pipeline.output_carrier(
        @check.unit_pipeline(checked, 0).unwrap(),
      ).unwrap()
      let rows = @carrier.complete_schema(
        @carrier.relation_rows(output).unwrap(),
      ).unwrap()
      assert_eq(@schema.field_count(rows), 1)
      let risk = @schema.field_at(rows, 0).unwrap()
      assert_eq(risk.name, @schema.Unqualified("risk"))
      assert_true(
        @contract.type_equal(
          risk.contract,
          @contract.primitive(@contract.StringType, nullable=true),
          100,
        ),
      )
    }
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(requests) =>
      raise @check.diagnostic_cause(@check.input_requests_diagnostic(requests))
  }
}

///|
fn source_infer_argument_expected() -> @program.Program {
  // Handwritten complete lowering expectation. The argument is evaluated in
  // its own derive before the retained input projection and common infer.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"objects":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"from":"objects","select":["id"]},{"distinct":["id"]},{"derive":{"aql_infer_argument_1":{"literal":"urgent"}}},{"select":["id","aql_infer_argument_1"],"as":"aql_infer_input_1"},{"from":"aql_infer_input_1","infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"aql_infer_argument_1"}}},"as":"aql_infer_outcome_1"},{"join":{"with":"aql_infer_input_1","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"id":"right.id","aql_infer_key_2":"left.id","aql_infer_role_3":"left.outcome","aql_infer_role_4":"left.value"}}},{"derive":{"aql_infer_result_5":{"object":{"input_key":{"object":{"id":{"field":"aql_infer_key_2"}}},"outcome":{"field":"aql_infer_role_3"},"value":{"field":"aql_infer_role_4"}}}}},{"select":["id",{"assessment":"aql_infer_result_5"}]},{"derive":{"aql_pipe_expr_2":{"property":{"name":"risk","value":{"property":{"name":"value","value":{"field":"assessment"}}}}}}},{"select":[{"risk":"aql_pipe_expr_2"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["risk"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Source INFER member lowering uses the common admitted prefix" {
  let environment = source_infer_member_environment()
  source_infer_member_check(source_infer_member_control(), environment)
  for
    path in [
      "assessment.value.risk", "assessment.VALUE.RISK", "`assessment`.`VaLuE`.`RiSk`",
    ] {
    let text = "FROM objects |> SELECT DISTINCT id |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = 'urgent') AS assessment |> SELECT " +
      path +
      " AS risk"
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      source_infer_member_context(environment),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_eq(body, semantic(source_infer_argument_expected()))
    assert_true(
      body.contains(
        "\"property\":{\"name\":\"risk\",\"value\":{\"property\":{\"name\":\"value\",\"value\":{\"field\":\"assessment\"}}}}",
      ),
      msg=path + " Program: " + body,
    )
    assert_true(body.contains("\"literal\":\"urgent\""), msg=body)
    assert_false(body.contains("aql_member_type_probe"))
    source_infer_member_check(actual, environment)
  }
}
