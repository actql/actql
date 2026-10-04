///|
fn client_composed_infer_test_program() -> PreparedClientProgram raise {
  let fixture = client_infer_prefix_test_program()
  let environment = @checked.checking_environment(
    @checked.checked_environment(@strategy.graph_program(fixture.graph)),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=@checked.checked_model_tasks(
      @strategy.graph_program(fixture.graph),
    ),
  )
  let document =
    #|{"version":"actql/0.1","id":"composed-infer","stages":[{"id":"left","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id","text"]}}},{"id":"right","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"tag":{"type":"string","nullable":false}},"rows":[{"id":"a","tag":"match"}]},"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id","tag"]}}},{"id":"classify","inputs":{"left_rows":{"result":{"stage":"left","result":"rows"}},"right_rows":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":2,"select":{"id":"left.id","text":"left.text"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"classify","result":"rows"}}}}
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  )
  match prepared {
    Ok(value) => value
    Err(Syntax(_)) => abort("composition fixture syntax")
    Err(Check(issue)) => raise @checked.diagnostic_cause(issue)
    Err(Graph(_)) => abort("composition fixture graph")
    Err(_) => abort("composition fixture preparation")
  }
}

///|
test "composed INFER selects its checked JOIN task rather than task zero" {
  let prepared = client_composed_infer_test_program()
  // The existing one-task component selection remains scoped to its input.
  assert_eq(prepared_client_infer_step(prepared), None)
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (2, 2, 2))
  assert_true(client_infer_occurrence_matches(occurrence, prepared))
  assert_true(
    !client_infer_occurrence_matches(
      occurrence,
      client_composed_infer_test_program(),
    ),
  )
  assert_true(
    physical_equal(
      occurrence.preparation,
      @strategy.graph_task_owner(prepared.graph, 2).unwrap(),
    ),
  )
}

///|
test "composition selection preserves the existing source-free occurrence" {
  let prepared = client_infer_prefix_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (0, 0, 2))
  assert_eq(prepared_client_infer_step(prepared), Some(2))
  assert_eq(
    client_infer_occurrence_model_task_cid(occurrence),
    prepared_client_infer_model_task_cid(prepared, 2),
  )
}

///|
test "composed egress binds the actual Unit and refuses changed or foreign authority" {
  let prepared = client_composed_infer_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let observed : Ref[ClientInferEgressObservation?] = Ref(
    Some({
      classification: @environment.Public,
      region: "fixture-region",
      provider_retention: false,
      training_use: false,
    }),
  )
  let admission = admit_client_infer_occurrence_egress(occurrence, execution, () => {
    observed.val
  }).unwrap()
  let graph = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(client_infer_egress_matches(admission, prepared, graph))
  assert_true(check_client_infer_egress_current(admission) is Ok(_))
  assert_true(
    admit_client_infer_occurrence_egress(
      occurrence,
      client_infer_graph_test_execution(client_infer_prefix_test_program()),
      () => observed.val,
    )
    is Err(ForeignOwner),
  )
  observed.val = Some({
    classification: @environment.Public,
    region: "elsewhere",
    provider_retention: false,
    training_use: false,
  })
  assert_true(
    check_client_infer_egress_current(admission) is Err(ChangedObservation),
  )
  observed.val = None
  assert_true(
    check_client_infer_egress_current(admission) is Err(MissingObservation),
  )
}

///|
test "joined task uses the existing Model barrier compiler with both inputs" {
  let prepared = client_composed_infer_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let issued = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(client_infer_plan_graph_coordinates(issued), (2, 2, 2))
  assert_true(client_infer_plan_graph_matches(issued, prepared, execution))
  assert_true(
    @checked.infer_item_limit_matches(
      issued.item_limit,
      @strategy.graph_program(prepared.graph),
      2,
      2,
    ),
  )
  assert_eq(@checked.infer_item_limit_maximum(issued.item_limit), 1L)
  let graph = parse_plan_identity_value(issued.graph.wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(graph, "nodes") is Some(@canonical.Array(nodes)) &&
    @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.object_field(graph, "root_refs") is Some(@canonical.Array(roots)) else {
    fail("complete joined Model component")
  }
  let nodes = @canonical.array_values(nodes)
  assert_eq(nodes.length(), 2)
  assert_eq(@canonical.array_values(edges).length(), 1)
  assert_eq(@canonical.array_values(roots).length(), 1)
  assert_true(
    @canonical.object_field(nodes[1], "node_id")
    is Some(@canonical.String("task_2_infer_2")),
  )
  let inputs = @canonical.object_field(nodes[0], "input_contracts").unwrap()
  assert_true(@canonical.object_field(inputs, "left_rows") is Some(_))
  assert_true(@canonical.object_field(inputs, "right_rows") is Some(_))
  assert_eq(issued.input.node_id, "task_2_before_infer_2")
  assert_eq(issued.output.node_id, "task_2_infer_2")
  assert_true(
    issue_prepared_client_composed_infer_plan_graph(
      occurrence,
      client_infer_graph_test_execution(client_infer_prefix_test_program()),
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(ForeignExecution),
  )
}

///|
test "common graph connects independent producers to JOIN and the Model barrier" {
  let prepared = client_composed_infer_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let component = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  let issued = issue_prepared_client_composed_task_plan_graph(
    prepared,
    component,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let graph = parse_plan_identity_value(issued.wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(graph, "nodes") is Some(@canonical.Array(nodes)) &&
    @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.object_field(graph, "root_refs") is Some(@canonical.Array(roots)) else {
    fail("complete common composed graph")
  }
  assert_eq(@canonical.array_values(nodes).length(), 4)
  assert_eq(@canonical.array_values(edges).length(), 3)
  let roots = @canonical.array_values(roots)
  assert_eq(roots.length(), 1)
  assert_true(
    @canonical.object_field(roots[0], "name")
    is Some(@canonical.String("answer")),
  )
  let from = @canonical.object_field(roots[0], "ref").unwrap()
  assert_true(
    @canonical.object_field(from, "node_id")
    is Some(@canonical.String("task_2_infer_2")),
  )
  assert_true(
    issue_prepared_client_composed_task_plan_graph(
      client_composed_infer_test_program(),
      component,
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(UnsupportedGraph),
  )
}

///|
fn client_composed_effect_test_environment(
  effect : @checked.CheckEnvironment,
) -> @checked.CheckEnvironment raise {
  let model = client_infer_prefix_test_program()
  let model_writer = @encode.writer(100000, 10000, 100)
  @environment.emit(
    @checked.checked_environment(@strategy.graph_program(model.graph)),
    model_writer,
  )
  let model_value = parse_plan_identity_value(
    @encode.finish(model_writer),
    100000,
    10000,
    100,
  ).unwrap()
  let tasks = @canonical.object_field(model_value, "model_task_contracts").unwrap()
  let effect_writer = @encode.writer(100000, 10000, 100)
  @environment.emit(@checked.checking_environment_wire(effect), effect_writer)
  let effect_value = parse_plan_identity_value(
    @encode.finish(effect_writer),
    100000,
    10000,
    100,
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @encode.begin_object(writer)
  for (key, value) in @canonical.object_fields(effect_value).unwrap() {
    if key == "evidence_bundle_cid" {
      continue
    }
    @encode.key(writer, key)
    @canonical.emit_value(
      if key == "model_task_contracts" {
        tasks
      } else {
        value
      },
      writer,
    )
  }
  @encode.end_object(writer)
  let unsigned = parse_plan_identity_value(
    @encode.finish(writer),
    100000,
    10000,
    100,
  ).unwrap()
  let cid = @canonical.cid_value(unsigned, 100000, 10000, 100)
  let wire = @canonical.stringify_value(
    @canonical.object_with_string_field(unsigned, "evidence_bundle_cid", cid).unwrap(),
    100000,
    10000,
    100,
  )
  admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
test "Effect compiler keeps the original Model barrier and KEEP in one Plan" {
  let (_, base, limits) = client_composed_effect_base_fixture()
  let environment = client_composed_effect_test_environment(base)
  let document =
    #|{"version":"actql/0.1","id":"infer-effect","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true},"value":{"type":"number","nullable":false}},"rows":[{"id":"a","text":"hello","value":1}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"joined"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"inferred"},{"join":{"with":"joined","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"value":"right.value"}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let owner = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(owner) => owner
    Err(Candidate(@checked.Computation(issue))) => raise issue
    Err(Syntax(_)) => fail("Effect syntax")
    Err(Mapping(_)) => fail("Effect mapping")
    Err(Static(_)) => fail("Effect static")
    Err(Stage(_)) => fail("Effect stage")
    Err(Graph(_)) => fail("Effect graph")
    Err(_) => fail("composed Effect preparation")
  }
  let manifests = run_materials_manifests()
  assert_true(
    issue_prepared_client_effect_compilation(
      owner,
      manifests,
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
    )
    is Err(
      Graph(
        Fragment(
          Pipeline(Sequence(@lower.KernelFailure(2, @lower.MissingKernelNode)))
        )
      )
    ),
  )
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let component = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    manifests,
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(
    physical_equal(client_effect_compilation_owner(compilation), owner),
  )
  assert_true(physical_equal(compilation.compiled.infer.unwrap(), component))
  assert_eq(compilation.compiled.result_names, ["published"])
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "composed-scope", "composed-run", "2026-10-03T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let host_policy_wire = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let host_policy_cid = "sha256:" + @sha.hex(@utf8.encode(host_policy_wire))
  assert_true(
    client_effect_allowed_infer_run(allowed) is Err(MissingResultPolicy),
  )
  let model_run = client_effect_allowed_infer_run_with_policy_body(
    allowed,
    Some(host_policy_cid),
    Some(host_policy_wire),
    1024,
    100,
    8,
  ).unwrap()
  assert_true(
    client_effect_allowed_infer_run_with_policy_body(
      allowed,
      Some("sha256:" + "a".repeat(64)),
      Some(host_policy_wire),
      1024,
      100,
      8,
    )
    is Err(InvalidResultPolicy),
  )
  assert_true(client_compiled_run_matches_effect(model_run, owner, compilation))
  // Identical compilation bodies do not substitute their physical owner.
  let other_compilation = issue_prepared_client_effect_compilation(
    owner,
    manifests,
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_false(
    client_compiled_run_matches_effect(model_run, owner, other_compilation),
  )
  let original = client_compiled_run_source_free_result_policy_body(model_run).unwrap()
  let result_policy = @publication.captured_effect_dependency_body_cid(original)
  assert_true(
    result_policy !=
    @environment.model_task_data_handling_cid(
      @environment.model_execution_task(component.execution),
    ),
  )
  assert_eq(
    client_compiled_run_infer_observation_policy(model_run),
    Some(result_policy),
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(original),
    host_policy_wire,
  )
  assert_true(
    @publication.admit_captured_effect_dependency_body(
      "data_policy",
      Some(result_policy),
      @publication.captured_effect_dependency_body_json(original),
      1024,
      100,
      8,
    )
    is Ok(_),
  )
  assert_true(
    check_client_compiled_run_definition(model_run, definition) is Ok(_),
  )
  assert_true(
    client_infer_occurrence_matches_compiled_run(occurrence, model_run),
  )
  assert_true(
    physical_equal(client_compiled_run_infer(model_run).unwrap(), component),
  )
  // The Model component shares the Effect admission, but cannot use an
  // Effect-free invocation issuer or substitute a second Run owner.
  assert_true(
    issue_client_compiled_source_free_task_invocation(
      model_run,
      definition,
      "sha256:" + "d".repeat(64),
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  let plan = compilation.compiled.plan.plan
  let saved = admit_prepared_client_effect_compilation(
    owner,
    plan.wire,
    plan.fact_manifest_wire,
    @publication.run_evidence_value_json(compilation.compiled.template),
    @publication.publication_contract_json(compilation.compiled.compiled_plan),
    manifests,
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(physical_equal(client_effect_compilation_owner(saved), owner))
  assert_true(
    admit_prepared_client_effect_compilation(
      owner,
      plan.wire,
      plan.fact_manifest_wire,
      @publication.run_evidence_value_json(compilation.compiled.template),
      @publication.publication_contract_json(compilation.compiled.compiled_plan),
      manifests,
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
    )
    is Err(Issue(Graph(_))),
  )
  let foreign = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    issue_prepared_client_effect_compilation(
      foreign,
      manifests,
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
      infer=Some(component),
    )
    is Err(ForeignInferOwner),
  )
  let template = parse_plan_identity_value(
    @publication.run_evidence_value_json(compilation.compiled.template),
    100000,
    10000,
    100,
  ).unwrap()
  guard @canonical.object_field(template, "required_profile_contracts")
    is Some(@canonical.Array(profiles)) else {
    fail("Model profile remains bound by the Effect template")
  }
  assert_eq(@canonical.array_values(profiles).length(), 1)
}

///|
test "two acquired roots JOIN INFER KEEP and downstream Effect compile together" {
  let (_, _, base_limits) = client_composed_effect_base_fixture()
  let limits = {
    ..base_limits,
    program: client_standard_program_preparation_limits(),
  }
  let base = admit_client_check_environment(
    client_composed_acquired_effect_environment,
    "sha256:cd4aeacdc39164df2cf7e7cb74faf349a157677a5927d9e84379d0d8df2d91e7",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let environment = client_composed_effect_test_environment(base)
  let document =
    #|{"version":"actql/0.1","id":"two-source-infer-effect","stages":[{"id":"left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"right","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"classify","inputs":{"left_rows":{"result":{"stage":"left","result":"rows"}},"right_rows":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":2,"select":{"id":"left.id","value":"right.amount"}}},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]},"as":"joined"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"inferred"},{"join":{"with":"joined","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"value":"right.value"}}},{"select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}},{"id":"apply","inputs":{"classified":{"result":{"stage":"classify","result":"rows"}}},"steps":[{"filter":"value >= 1","as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}
  let owner = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(owner) => owner
    Err(Candidate(@checked.Computation(issue))) => raise issue
    Err(Syntax(_)) => fail("Effect syntax")
    Err(Mapping(_)) => fail("Effect mapping")
    Err(Static(_)) => fail("Effect static")
    Err(Stage(_)) => fail("Effect stage")
    Err(Graph(_)) => fail("Effect graph")
    Err(_) => fail("acquired composed Effect preparation")
  }
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (2, 2, 3))
  assert_true(
    issue_prepared_client_effect_compilation(
      owner,
      run_materials_manifests(),
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
    )
    is Err(
      Graph(
        Fragment(
          Pipeline(Sequence(@lower.KernelFailure(3, @lower.MissingKernelNode)))
        )
      )
    ),
  )
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let component = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(
    physical_equal(client_effect_compilation_owner(compilation), owner),
  )
  assert_eq(compilation.compiled.result_names, ["published"])
  // Both independent captures remain prerequisites of the actual JOIN task.
  assert_eq(@strategy.graph_captured_prefix(occurrence.owner.graph), 2)
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let model_run = client_effect_allowed_infer_run(allowed).unwrap()
  let source_policy = prepared_client_effect_publication_data_policy_cid(owner)
  assert_true(source_policy is Some(_))
  assert_true(
    client_effect_allowed_infer_run_with_policy_body(
      allowed,
      source_policy,
      Some(
        "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
      ),
      1024,
      100,
      8,
    )
    is Err(InvalidResultPolicy),
  )
  assert_true(
    client_compiled_run_source_free_result_policy_body(model_run) is None,
  )
  assert_eq(
    client_compiled_run_infer_observation_policy(model_run),
    source_policy,
  )
  // The two declared source policies are unknown. A public provider-side
  // observation must not make their combined input eligible for dispatch.
  assert_true(
    admit_client_infer_occurrence_egress(occurrence, execution, () => {
      Some({
        classification: @environment.Public,
        region: "fixture-region",
        provider_retention: false,
        training_use: false,
      })
    })
    is Err(UnknownClassification),
  )
}
