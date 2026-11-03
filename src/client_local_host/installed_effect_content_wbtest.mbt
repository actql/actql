///|
fn installed_effect_content_fixture(
  rows? : String = "[{\"id\":1}]",
  keep_content? : Bool = false,
) -> ClientInstalledEffectContentPreparation {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"managed-content-effect","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"selected"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":1,"max_bytes":32}},"as":"attachment"},{"derive":{"id":"row_count"}},{"select":["id"],"as":"statistics"}],"results":{"out":{"from":"statistics","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let document = document.replace(
    old="\"rows\":[{\"id\":1}]",
    new="\"rows\":" + rows,
  )
  let document = if keep_content {
    document
    .replace(
      old=",{\"derive\":{\"id\":\"row_count\"}},{\"select\":[\"id\"],\"as\":\"statistics\"}",
      new="",
    )
    .replace(
      old="\"from\":\"statistics\",\"fields\":[\"id\"]",
      new="\"from\":\"attachment\",\"fields\":[\"name\",\"content\",\"media_type\",\"size_bytes\",\"row_count\"]",
    )
    .replace(
      old="\"id\":\"id\",\"set\":{\"Name\":{\"field\":\"id\"}}",
      new="\"id\":\"row_count\",\"set\":{\"Name\":{\"field\":\"row_count\"}}",
    )
  } else {
    document
  }
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
    source_free_policy=Some(policy),
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "content-plan", "same-original", "2026-10-26T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = @publication_host.client_effect_allowed_serialization_run(
    allowed,
  ).unwrap()
  let component = @publication_host.client_compiled_run_serialization(compiled).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: source_capture_values(),
      output_values: source_capture_values(),
    },
    max_work: 100000,
    max_frames: 100,
  }
  prepare_installed_effect_content(
    prepared,
    compiled,
    compilation,
    definition,
    component,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    { max_work: 100000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    original_keyed_content_workspace(),
    {
      cancel: () => abort("no physical work while preparing"),
      stopped: () => abort("no physical work while preparing"),
      cleanup: () => abort("no physical work while preparing"),
    },
    _ => abort("no Content child while preparing"),
  ).unwrap()
}

///|
test "Effect Content plan retains and quotes the same original family without physical entry" {
  let content = installed_effect_content_fixture()
  assert_false(
    installed_managed_owner_shape_supported(Effect(content.prepared), false),
  )
  assert_true(
    installed_managed_owner_shape_supported(
      Effect(content.prepared),
      false,
      content=Some(content),
    ),
  )
  assert_false(
    installed_managed_owner_shape_supported(
      Effect(content.prepared),
      true,
      content=Some(content),
    ),
  )
  let foreign = installed_effect_content_fixture()
  assert_false(
    installed_managed_owner_shape_supported(
      Effect(content.prepared),
      false,
      content=Some(foreign),
    ),
  )
  assert_true(
    physical_equal(installed_effect_content_provider(content), content.provider),
  )
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    content.prepared,
    "sha256:" + "a".repeat(64),
    "content-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    content.prepared,
    0,
    "save",
    [
      prepare_installed_effect_operation_extent(
        "fixture",
        @execution.execution_capacity(1L, 1L).unwrap(),
        0L,
        false,
      ).unwrap(),
    ],
    [],
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    content.prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    content=Some(content),
    provider_factory=_ => [],
  ).unwrap()
  assert_true(physical_equal(plan.content.unwrap(), content))
  assert_true(plan.limits.retained_bytes > 0L)
  assert_true(plan.limits.execution_bytes > 0L)
  assert_eq(plan.limits.attempts, 1)
}

///|
test "serialization output bound preserves empty and larger original input demand" {
  let hundred = "[" +
    Array::makei(100, index => "{\"id\":" + index.to_string() + "}").join(",") +
    "]"
  for
    (input, count) in [
      ("[]", 0),
      ("[{\"id\":1}]", 1),
      ("[{\"id\":1},{\"id\":2},{\"id\":3}]", 3),
      (hundred, 100),
    ] {
    let original = installed_effect_content_fixture(rows=input)
    assert_eq(client_serialization_input_row_bound(original.component), Some(count))
    let graph = installed_managed_owner_graph(Effect(original.prepared))
    let owner = @strategy.graph_task_owner(graph, 0).unwrap()
    let prepared = @lower.bound_preparation(owner)
    let node = @lower.node_at(prepared, 1).unwrap()
    assert_eq(@lower.prepared_closed_row_bound(prepared, 10000, target_step=Some(0)).unwrap().0, count)
    assert_eq(@lower.prepared_closed_row_bound(prepared, 0, target_step=Some(0)), None)
    assert_eq(@lower.prepared_closed_row_bound(prepared, 10000, target_step=Some(-1)), None)
    assert_eq(@lower.prepared_closed_row_bound(prepared, 10000, target_step=Some(@lower.node_count(prepared))), None)
    assert_eq(@lower.node_row_count_bound(node, [count]), Some(1))
    assert_eq(@lower.node_input_independent_row_count_bound(node), Some(1))
    assert_eq(@lower.node_row_count_bound(node, [-1]), None)
    assert_eq(@lower.node_row_count_bound(node, []), None)
    assert_eq(
      @lower.prepared_closed_row_bound(prepared, 10000).unwrap().0,
      Int::max(1, count),
    )
  }
}

///|
test "one checked serialized row quotes Local STORE without bypassing the parent ceiling" {
  let content = installed_effect_content_fixture(keep_content=true)
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    content.prepared,
    "sha256:" + "a".repeat(64),
    "local-store-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  // Existing Common/Local/SQLite limits and the native-profile test envelope.
  // File transfer remains separate from this retained-memory requirement.
  let recipe = local_file_store_recipe_fixture().unwrap()
  let capture = prepare_installed_effect_capture_recipe_extent(
    "files.write.capture", recipe,
  ).unwrap()
  let request_extent = prepare_installed_effect_operation_extent(
    "files.write.request",
    recipe[2],
    0L,
    false,
  ).unwrap()
  let physical = prepare_installed_effect_operation_extent(
    "files.write",
    recipe[3],
    16777216L,
    true,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand_with_controls(
    content.prepared,
    0,
    "save",
    [capture],
    [request_extent, physical],
    recipe[4],
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    content.prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    content=Some(content),
    provider_factory=_ => [],
  ).unwrap()
  assert_eq(plan.rows, 1)
  assert_true(plan.limits.retained_bytes <= 536870912L)
  assert_true(plan.limits.execution_bytes <= 536870912L)
  assert_true(
    installed_effect_limits_fit(plan.limits, {
      ..plan.limits,
      retained_bytes: 536870912L,
      execution_bytes: 536870912L,
    }),
  )
  assert_eq(
    plan.limits.transfer_bytes,
    plan._observed_compute_limits.transfer_bytes + 16777216L,
  )
}

///|
test "installed Content node bound is original-contextual and never a global reference bound" {
  let content = installed_effect_content_fixture(keep_content=true)
  let owner = @lower.serialization_owner(content.component.barrier)
  let (contract, nodes, _) = installed_content_schema_node_bound(
    content, owner, 10000,
  ).unwrap()
  assert_eq(nodes, content.reference_nodes)
  assert_true(
    client_local_json_contract_nodes(contract, Ref(10000), 100) is None,
  )
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    @pipeline.Step(content.component.step),
  ).unwrap()
  assert_true(client_local_json_schema_nodes(schema, 10000, 100) is None)
  assert_eq(
    client_local_json_schema_nodes(
      schema,
      10000,
      100,
      content=Some((contract, nodes)),
    ).unwrap().0,
    nodes.to_int64() + 5L,
  )
  let foreign = installed_effect_content_fixture(keep_content=true)
  assert_true(
    installed_content_schema_node_bound(foreign, owner, 10000) is None,
  )
  assert_true(installed_content_schema_node_bound(content, owner, 0) is None)
}
