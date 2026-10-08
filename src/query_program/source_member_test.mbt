///|
// ASCII canonical preimages and SHA-256 pins are independently computed with
// Python hashlib; complete bodies remain in source-member-catalog-independent.json.
// This is a real Catalog admission fixture, not a public execution receipt.
fn source_member_environment() -> @check.CheckEnvironment raise {
  let result = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:232d374fc64aa44fe8fe5f713807e4f92ede7695c1b89354ac13e4c6779df153","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"payload":{"additional_properties":false,"fields":{"score":{"nullable":true,"type":"number"}},"nullable":true,"type":"object"}},"nullable":false,"type":"object"},"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:82062d0e4efb4df3d93c732e93b6b52038e642d9004d7a5c288509b8feaa4268","output":{"carrier":"relation","data_policy":{"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"payload":{"additional_properties":false,"fields":{"score":{"nullable":true,"type":"number"}},"nullable":true,"type":"object"}},"nullable":false,"type":"object"},"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:af8b9018c7db6dc3dbd47e2a237a95b03eb8fe72d3b3304fd4f68c85ff0e6e4a","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:82062d0e4efb4df3d93c732e93b6b52038e642d9004d7a5c288509b8feaa4268","output":{"carrier":"relation","data_policy":{"cid":"sha256:2046b5c645c232716da96e348ff14b3f0c772451d0bd6369ebc804ca9d37bbd7","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:cd9694025262c09843a35bbd73c9d63fc30cf111188c7b25c447b5772cdf2370","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:af8b9018c7db6dc3dbd47e2a237a95b03eb8fe72d3b3304fd4f68c85ff0e6e4a",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  )
  let wire = match result {
    Ok(wire) => wire
    Err(issue) =>
      fail("independent Environment admission: " + @debug.to_string(issue))
  }
  @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    graph=true,
  )
}

///|
fn source_member_context(captured? : Bool = false) -> Context raise {
  let environment = source_member_environment()
  let prepared = match
    @check.prepare_source_catalog(environment, {
      max_work: 1000000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }) {
    Ok(prepared) => prepared
    Err(@check.EnvironmentFailure::References(issue)) =>
      fail("independent Catalog references: " + @debug.to_string(issue.kind))
    Err(issue) => raise issue
  }
  let catalog = @check.source_catalog_contracts(prepared)
  let declaration = @wire.admit(
    @source.parse_json(
      (
        #|{"connector":"crm/main","resource":"r","view":"v"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let schema = @environment.read_relation_schema_fields(
      @wire.lookup(
        @wire.open_object(
          @environment.member_body(
            @environment.member_at(
              @check.checking_environment_wire(environment),
              @environment.ContractRegistry,
              4,
            ).unwrap(),
          ),
        ).unwrap(),
        "body",
      )
      .bind(body => @wire.lookup(@wire.open_object(body).unwrap(), "fields"))
      .unwrap(),
      10000,
      100,
      100,
      100000,
    ).unwrap().0
  {
    ..graph_projection_property_context(),
    captured_stage: if captured {
      Some("capture")
    } else {
      None
    },
    source_catalog: Some(catalog),
    input_schemas: [("objects", schema)],
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: Captured(declaration),
        visible_fields: ["id", "payload"],
        graph_bindings: [],
      },
    ],
  }
}

///|

///|
fn source_member_expected(captured? : Bool = false) -> @program.Program {
  let text = if captured {
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"capture","inputs":{"objects":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"from":"objects","filter":{"literal":true}},{"select":["id","payload"],"as":"aql_capture_0"}],"results":{"source":{"from":"aql_capture_0","fields":["id","payload"]}}},{"id":"main","inputs":{"objects":{"result":{"stage":"capture","result":"source"}}},"steps":[{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"objects","key":["id"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"payload","to":"payload"}]}}]}],"edges":[]},"as":"aql_data_1"},{"from":"aql_data_1","match_nodes":{"definition":"N","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","payload"],"label":"Person"},"as":"aql_keyed_seeds_3"},{"from":"aql_keyed_seeds_3","derive":{"aql_query_expr_1":{"property":{"name":"score","value":{"field":"payload"}}}}},{"select":["id",{"score":"aql_query_expr_1"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    )
  } else {
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"objects":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"objects","key":["id"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"payload","to":"payload"}]}}]}],"edges":[]},"as":"aql_data_1"},{"from":"aql_data_1","match_nodes":{"definition":"N","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","payload"],"label":"Person"},"as":"aql_keyed_seeds_2"},{"from":"aql_keyed_seeds_2","derive":{"aql_query_expr_1":{"property":{"name":"score","value":{"field":"payload"}}}}},{"select":["id",{"score":"aql_query_expr_1"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    )
  }
  @program.parse(text, construction_limits().program, format=Json).unwrap()
}

///|
test "Source Graph members retain the real Source and independent Program" {
  // Handwritten expected Program preserves the original Source, complete
  // capture, Graph keys/labels and final projected columns. No probe is emitted.
  let expected = source_member_expected()
  let context = source_member_context()
  let source = @stage_parameters.prepare(expected, {
    max_parameters: 100,
    max_nodes: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
  }).unwrap()
  let (views, locals) = @check_context.prepare_source_registrations(
    source,
    context.source_catalog.unwrap(),
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
    max_inputs=100,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let (wiring, _) = match
    @check_context.prepare_sourceview_program(views, locals, {
      max_stages: 20,
      max_steps: 100,
      max_results: 100,
      max_work: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    }) {
    Ok(value) => value
    Err(
      @check_context.SourceViewProgramIssue::Program(
        @stage_results.LocalProgramIssue::Pipeline(stage, issue)
      )
    ) =>
      fail(
        "independent Source pipeline stage " +
        stage.to_string() +
        ": " +
        @debug.to_string(issue.kind),
      )
    Err(
      @check_context.SourceViewProgramIssue::Program(
        @stage_results.LocalProgramIssue::Results(stage, issue)
      )
    ) =>
      fail(
        "independent Source results stage " +
        stage.to_string() +
        ": " +
        @debug.to_string(issue.kind),
      )
    Err(
      @check_context.SourceViewProgramIssue::Program(
        @stage_results.LocalProgramIssue::Import(stage, issue)
      )
    ) =>
      fail(
        "independent Source import stage " +
        stage.to_string() +
        ": " +
        @debug.to_string(issue),
      )
    Err(
      @check_context.SourceViewProgramIssue::Program(
        @stage_results.LocalProgramIssue::Order(
          stage,
          @relation_results.ResultOrder(issue)
        )
      )
    ) =>
      fail(
        "independent Source result order stage " +
        stage.to_string() +
        ": " +
        @debug.to_string(issue.kind),
      )
    Err(_) =>
      fail("independent Source Program preparation outside pipeline typing")
  }
  let pipeline = @pipeline_parameters.pipeline(
    @stage_parameters.collection(
      @stage_results.stage_port_source(
        @stage_results.wiring_stage_at(wiring, 0).unwrap(),
      ),
    ),
  )
  let rows = @carrier.complete_schema(
    @carrier.relation_rows(@pipeline.output_carrier(pipeline).unwrap()).unwrap(),
  ).unwrap()
  assert_eq(@schema.field_count(rows), 2)
  let id = @schema.field_at(rows, 0).unwrap()
  let score = @schema.field_at(rows, 1).unwrap()
  assert_eq(id.name, @schema.Unqualified("id"))
  assert_false(id.contract.nullable)
  assert_eq(score.name, @schema.Unqualified("score"))
  assert_true(score.contract.nullable)
  for
    tail in [
      "SELECT a.id AS id, a.payload.SCORE AS score", "SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`ScOrE` AS score",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(
        graph_projection_property_source(tail),
        syntax_limits(),
      ).unwrap(),
      context,
      { ..construction_limits(), max_expression_work: 100000, },
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    assert_false(semantic(actual).contains("aql_member_type_probe"))
  }
}

///|
test "Source member Context rejects a foreign generation or ModelTask owner" {
  let environment = source_member_environment()
  let wire = @check.checking_environment_wire(environment)
  let catalog = @check.source_catalog_contracts(
    @check.prepare_source_catalog(environment, {
      max_work: 1000000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
  )
  let cid = @environment.cid(wire)
  let context = @frontend.bind_query_context(
    [],
    cid,
    source_catalog=Some(catalog),
  ).unwrap()
  assert_true(physical_equal(context.source_catalog.unwrap(), catalog))
  assert_true(
    @frontend.bind_query_context(
      [],
      "sha256:foreign",
      source_catalog=Some(catalog),
    )
    is Err(@frontend.EnvironmentMismatch),
  )
  // Equal canonical content is insufficient to substitute a different owner.
  let foreign = @check.checking_environment_wire(source_member_environment())
  assert_eq(@environment.cid(foreign), cid)
  assert_false(physical_equal(foreign, wire))
  let task_limits : @environment.ModelTaskLimits = {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 100,
    },
    contracts: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
    max_work: 1000000,
  }
  let tasks = @environment.check_model_tasks(wire, task_limits).unwrap()
  assert_true(
    @frontend.bind_query_context(
      [],
      cid,
      source_catalog=Some(catalog),
      model_tasks=Some(tasks),
    )
    is Ok(_),
  )
  let foreign_tasks = @environment.check_model_tasks(foreign, task_limits).unwrap()
  assert_true(
    @frontend.bind_query_context(
      [],
      cid,
      source_catalog=Some(catalog),
      model_tasks=Some(foreign_tasks),
    )
    is Err(@frontend.EnvironmentMismatch),
  )
}

///|
test "Source member binding retains the expression work refusal" {
  let result = compile_query_script(
    @query.parse_query_script(
      graph_projection_property_source("SELECT a.payload.SCORE AS score"),
      syntax_limits(),
    ).unwrap(),
    source_member_context(),
    { ..construction_limits(), max_expression_work: 1, },
  )
  assert_true(result is Err(Expression({ issue: @expression.WorkLimit, .. })))
}

///|
test "Source object capture retains the common unresolved-order refusal" {
  // This is a separate unresolved common boundary, not positive public
  // acceptance. Neither a Source key nor an order witness is invented here.
  let context = source_member_context(captured=true)
  let source = @stage_parameters.prepare(
    source_member_expected(captured=true),
    {
      max_parameters: 100,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let (views, locals) = @check_context.prepare_source_registrations(
    source,
    context.source_catalog.unwrap(),
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
    max_inputs=100,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let result = @check_context.prepare_sourceview_program(views, locals, {
    max_stages: 20,
    max_steps: 100,
    max_results: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
  })
  assert_true(
    result
    is Err(
      @check_context.SourceViewProgramIssue::Program(
        @stage_results.LocalProgramIssue::Order(
          0,
          @relation_results.ResultOrder(
            { kind: @relation_results.UnresolvedOrder, .. }
          )
        )
      )
    ),
  )
}
