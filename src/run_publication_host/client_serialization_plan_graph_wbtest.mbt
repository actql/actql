///|
fn serialization_plan_test_policy() -> @publication.CapturedEffectDependencyBody {
  admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
}

///|
test "Serialize Plan keeps checked defaults ceilings policy and original Result roots" {
  let owner = serialization_preparation_test_program(
    detour=true,
    projected=true,
  )
  assert_eq(prepared_client_serialization_occurrences(owner), [(0, 2)])
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  assert_eq(
    prepared_client_serialization_occurrences(
      prepare_effect_free_client_program(
        run_materials_document,
        Json,
        environment,
        None,
        run_materials_limits().preparation,
      ).unwrap(),
    ),
    [],
  )
  let component = issue_prepared_client_serialization_plan_graph(
    owner,
    0,
    2,
    serialization_plan_test_policy(),
    100,
    1000,
    3,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(client_serialization_plan_graph_coordinates(component), (0, 2))
  assert_eq((component.max_rows, component.max_bytes), (2, 128))
  assert_eq(component.input.node_id, "task_0_before_serialize_2")
  assert_true(component.input.wire.contains("values_1"))
  let node = parse_plan_identity_value(
    component.output.wire,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    @canonical.object_field(node, "kind")
    is Some(@canonical.String("content_barrier")),
  )
  assert_true(
    @canonical.object_field(node, "profile_id")
    is Some(@canonical.String("actql-content/0.1")),
  )
  let barrier = @canonical.object_field(node, "barrier").unwrap()
  let options = @canonical.object_field(barrier, "serialization").unwrap()
  // Independent normalized options, not an expectation rendered by the new
  // profile emitter. Host ceilings are tightened by the original author guards.
  assert_eq(
    @canonical.stringify_value(options, 10000, 1000, 20),
    "{\"bounds\":{\"max_bytes\":128,\"max_rows\":2},\"encoding\":\"utf-8\",\"fields\":[\"id\"],\"format\":\"jsonl\",\"line_ending\":\"lf\",\"name\":\"out.jsonl\",\"preserve_order\":true}",
  )
  assert_true(
    @canonical.object_field(barrier, "effective_output_data_policy_cid")
    is Some(
      @canonical.String(
        "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
      )
    ),
  )
  let graph = parse_plan_identity_value(
    client_serialization_plan_graph_wire(component),
    100000,
    10000,
    100,
  ).unwrap()
  guard @canonical.object_field(graph, "nodes") is Some(@canonical.Array(nodes)) else {
    fail("missing nodes")
  }
  assert_eq(@canonical.array_values(nodes).length(), 3)
  guard @canonical.object_field(graph, "root_refs")
    is Some(@canonical.Array(roots)) else {
    fail("missing roots")
  }
  assert_eq(@canonical.array_values(roots).length(), 1)
  assert_eq(component.graph.transformations.length(), 1)
  assert_true(physical_equal(component.graph.transformations[0].owner, owner))
  assert_true(!component.graph.wire.contains("REL.serialize"))
}

///|
test "Serialize Plan preserves empty type limits and includes the physical internal sort" {
  let owner = serialization_preparation_test_program(empty=true)
  let zero = issue_prepared_client_serialization_plan_graph(
    owner,
    0,
    1,
    serialization_plan_test_policy(),
    0,
    0,
    3,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq((zero.max_rows, zero.max_bytes), (0, 0))
  assert_true(
    issue_prepared_client_serialization_plan_graph(
      owner,
      0,
      1,
      serialization_plan_test_policy(),
      -1,
      100,
      3,
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    issue_prepared_client_serialization_plan_graph(
      owner,
      1,
      1,
      serialization_plan_test_policy(),
      100,
      100,
      3,
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(UnsupportedGraph),
  )
  assert_true(
    issue_prepared_client_serialization_plan_graph(
      owner,
      0,
      1,
      serialization_plan_test_policy(),
      100,
      100,
      2,
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(Preparation(Barrier({ kind: BudgetExceeded, .. }))),
  )
  assert_true(
    issue_prepared_client_serialization_plan_graph(
      serialization_preparation_test_program(ordered=true),
      0,
      1,
      serialization_plan_test_policy(),
      100,
      100,
      3,
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Ok(component) &&
    component.input.wire.contains("REL.orderByStable") &&
    component.input.output_contract_cid != component.output.output_contract_cid,
  )
}

///|
test "Serialize compilation binds the Content profile without claiming pure acquisition" {
  let owner = serialization_preparation_test_program(projected=true)
  let component = issue_prepared_client_serialization_plan_graph(
    owner,
    0,
    1,
    serialization_plan_test_policy(),
    2,
    128,
    3,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = issue_prepared_client_serialization_compilation(
    owner,
    component,
    run_materials_manifests(),
    1000,
    1000,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    client_task_compilation_serialization(compilation) is Some(saved) &&
    physical_equal(saved, component),
  )
  assert_eq(client_task_compilation_result_names(compilation), ["file"])
  let plan = parse_plan_identity_value(
    client_task_executable_plan_wire(compilation.plan),
    100000,
    10000,
    100,
  ).unwrap()
  let template = parse_plan_identity_value(
    @publication.run_evidence_value_json(compilation.template),
    100000,
    10000,
    100,
  ).unwrap()
  let expected_profiles = "[{\"contract_cid\":\"" +
    @environment.compiler_content_barrier_contract_cid() +
    "\",\"profile_id\":\"actql-content/0.1\"}]"
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(plan, "required_profiles").unwrap(),
      10000,
      1000,
      20,
    ),
    expected_profiles,
  )
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(template, "required_profile_contracts").unwrap(),
      10000,
      1000,
      20,
    ),
    expected_profiles,
  )
  let compiled = parse_plan_identity_value(
    @publication.publication_contract_json(compilation.compiled_plan),
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    @canonical.object_field(compiled, "aoa_logical_cid")
    is Some(@canonical.String(cid)) &&
    cid == component.input.logical_cid,
  )
  let run = issue_client_task_compiled_run(
    owner,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(client_compiled_run_matches(run, owner))
  assert_true(
    client_compiled_run_source_free_result_policy_body(run) is Some(original) &&
    physical_equal(original, component.policy),
  )
  assert_true(
    issue_client_task_source_free_invocation(
      compilation, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      100000, 10000, 100,
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_generation")),
  )
  assert_true(
    issue_prepared_client_serialization_compilation(
      serialization_preparation_test_program(projected=true),
      component,
      run_materials_manifests(),
      1000,
      1000,
      100000,
      10000,
      100,
    )
    is Err(ForeignSerializationOwner),
  )
  assert_true(
    issue_prepared_client_serialization_compilation(
      owner,
      component,
      run_materials_manifests(),
      1000,
      1000,
      1,
      10000,
      100,
    )
    is Err(_),
  )
}
