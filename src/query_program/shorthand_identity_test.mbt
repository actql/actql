///|
// Use the existing checked identity owner, rather than hashing frontend output.
fn check_shorthand_identity_program(
  program : @program.Program,
  environment : @check.CheckEnvironment,
) -> @check.CheckedProgram raise {
  match @check.check_parsed(program, environment, None, check_limits()) {
    Checked(checked) => checked
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed shorthand identity control")
  }
}

///|
fn shorthand_checked_semantics(checked : @check.CheckedProgram) -> String raise {
  let definition = @check_context.program_identity_definition(
    @check.source_identity(checked),
  )
  let writer = @encode.writer(100000, 10000, 100)
  @references.emit_program_semantics(
    @references.program_definition_semantics(definition),
    writer,
  )
  @encode.finish(writer)
}

///|
fn assert_shorthand_checked_schema(
  actual : @schema.Schema,
  expected : @schema.Schema,
) -> Unit raise {
  assert_eq(@schema.field_count(actual), @schema.field_count(expected))
  for index in 0..<@schema.field_count(expected) {
    let actual = @schema.field_at(actual, index).unwrap()
    let expected = @schema.field_at(expected, index).unwrap()
    assert_eq(actual.name, expected.name)
    assert_eq(actual.presence, expected.presence)
    assert_true(@contract.type_equal(actual.contract, expected.contract, 10000))
  }
}

///|
fn assert_shorthand_checked_identity(
  actual : @check.CheckedProgram,
  expected : @check.CheckedProgram,
) -> Unit raise {
  assert_eq(
    shorthand_checked_semantics(actual),
    shorthand_checked_semantics(expected),
  )
  assert_eq(
    @check_context.program_identity_definition_cid(
      @check.source_identity(actual),
    ),
    @check_context.program_identity_definition_cid(
      @check.source_identity(expected),
    ),
  )
  assert_true(@check.unit_count(expected) > 0)
  assert_eq(@check.unit_count(actual), @check.unit_count(expected))
  for index in 0..<@check.unit_count(expected) {
    assert_eq(
      @check.unit_definition_cid(actual, index).unwrap(),
      @check.unit_definition_cid(expected, index).unwrap(),
    )
    let actual_pipeline = @check.unit_pipeline(actual, index).unwrap()
    let expected_pipeline = @check.unit_pipeline(expected, index).unwrap()
    assert_eq(
      @pipeline.step_count(actual_pipeline),
      @pipeline.step_count(expected_pipeline),
    )
    for step in 0..<@pipeline.step_count(expected_pipeline) {
      let actual_step = @pipeline.step_at(actual_pipeline, step).unwrap()
      let expected_step = @pipeline.step_at(expected_pipeline, step).unwrap()
      assert_eq(actual_step.input, expected_step.input)
      assert_eq(actual_step.binding_name, expected_step.binding_name)
      assert_shorthand_checked_schema(
        @pipeline.step_schema(actual_step).unwrap(),
        @pipeline.step_schema(expected_step).unwrap(),
      )
    }
    assert_shorthand_checked_schema(
      @pipeline.output_schema(actual_pipeline).unwrap(),
      @pipeline.output_schema(expected_pipeline).unwrap(),
    )
  }
}

///|
// Mapping, catalog and environment CIDs are independent sorted-JSON SHA-256
// fixture preimages, using the existing checked local UPDATE fixture contract.
fn update_shorthand_environment() -> @check.CheckEnvironment {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:c3855ab77c68b3eba9e41f5e1125ec5068bed71283b5b4641c5596ecb7deb38b","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]},{"effect_kind":"update","permissions":["scope:update"],"selector_class":"ids","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:c3855ab77c68b3eba9e41f5e1125ec5068bed71283b5b4641c5596ecb7deb38b",
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
  @check.checking_environment(wire, { text_time: false, veca: false, }, {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  })
}

///|
fn update_shorthand_checked_owner(
  name : String,
  environment : @check.CheckEnvironment,
) -> @check.EffectProgramStaticCandidate {
  let source = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"number","nullable":false}},"rows":[{"id":"original-id","value":1}]},"as":"updates_source"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..infer_member_context(environment),
    inputs: [
      {
        relation: [{ value: "updates_source", quoted: false, }],
        name: "updates_source",
        source: GeneratedValues(source),
        visible_fields: ["id", "value"],
        graph_bindings: [],
      },
    ],
  }
  let program = compile(
    @query.parse_query(
      "FROM updates_source |> RESULT updates |> EFFECT " +
      name +
      "UPDATE TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1` FROM RESULT updates ID id SET (Name = value)",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let candidate = @check.prepare_effect_computation_candidate(
    program,
    environment,
    None,
    [],
    check_limits(),
    1,
    100,
  ).unwrap()
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
    1000,
  ).unwrap()
  @check.close_effect_computation_static(candidate, mappings, {
    max_members: 1,
    max_work: 1000,
    max_admission_nodes: 100,
    max_admission_depth: 10,
    max_admission_text_bytes: 1000,
  }).unwrap()
}

///|
test "anonymous UPDATE retains checked semantics definition and Effect identity" {
  let environment = update_shorthand_environment()
  let expected = update_shorthand_checked_owner(
    "aql_update_effect ", environment,
  )
  for name in ["", "`aql_update_effect` ", "/*😀*/\r\n"] {
    let actual = update_shorthand_checked_owner(name, environment)
    assert_shorthand_checked_identity(
      @check.effect_program_static_checked_computation(actual),
      @check.effect_program_static_checked_computation(expected),
    )
    assert_eq(
      @check.effect_program_static_definition_cid(actual),
      @check.effect_program_static_definition_cid(expected),
    )
    assert_eq(
      @check.effect_program_static_semantics_cid(actual),
      @check.effect_program_static_semantics_cid(expected),
    )
    let headers = @check.effect_program_static_headers(actual)
    assert_eq(@program.effect_header_count(headers), 1)
    assert_eq(
      @program.effect_header_id(@program.effect_header_at(headers, 0).unwrap()),
      "aql_update_effect",
    )
    let effects = @check.effect_program_static_effects(actual)
    let bindings = @stage_results.effect_static_candidate_results(effects)
    assert_eq(@stage_results.effect_result_binding_count(bindings), 1)
    assert_true(
      @stage_results.effect_result_binding_result(
        @stage_results.effect_result_binding_at(bindings, 0).unwrap(),
      )
      is Some(_),
    )
  }
  for
    (name, exact) in [
      ("save ", "save"),
      ("`Save.Exact` ", "Save.Exact"),
      ("UPDATE ", "UPDATE"),
    ] {
    let actual = update_shorthand_checked_owner(name, environment)
    assert_false(
      @check.effect_program_static_definition_cid(actual) ==
      @check.effect_program_static_definition_cid(expected),
    )
    assert_false(
      @check.effect_program_static_semantics_cid(actual) ==
      @check.effect_program_static_semantics_cid(expected),
    )
    let header = @program.effect_header_at(
      @check.effect_program_static_headers(actual),
      0,
    ).unwrap()
    assert_eq(@program.effect_header_id(header), exact)
  }
}
