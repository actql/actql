///|
fn property_execution_steps() -> String {
  (
    #|[{"values":{"schema":{"id":{"type":"number","nullable":true}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"p_copy":"$p","n_copy":"$n"}},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"]},{"name":"Other","from":"seed","key":["id"]}],"edges":[{"name":"E","from":"seed","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["id"]}}]},"as":"g"}]
  )
}

///|
fn property_execution_policy_body() -> String {
  (
    #|{"max_aggregate_array_items":7,"max_artifact_bytes":7,"max_artifact_rows":7,"max_effect_items":7,"max_graph_construction_edges":5,"max_graph_construction_input_rows":7,"max_graph_construction_nodes":3,"max_graph_input_edges":7,"max_graph_input_nodes":7,"max_graph_output_rows":7,"max_graph_paths":7,"max_infer_items":7,"max_model_input_tokens_per_item":7,"max_model_request_bytes_per_item":7,"max_model_total_duration_ms":7,"max_nested_value_bytes":7,"max_nested_value_depth":7,"max_relation_output_rows":7,"max_temporal_matches_per_key":3,"max_temporal_output_rows":7,"version":"actql-capacity-host-policy/0.1"}
  )
}

///|
fn property_execution_policy() -> @policy.Policy {
  @policy.admit(
    @utf8.encode(property_execution_policy_body()),
    // Independently hash the authored canonical policy, not product output.
    "sha256:68b3117e9107a0ebe3700bbaf979f3ba0a1e1bede3579ebbd38eb152d97e6029",
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
}

///|
fn property_execution_host_profile() -> String {
  bound_profile().replace(
    old=capacity_profile(false).replace(old="}}", new="}"),
    new="{\"capacity\":" + property_execution_policy_body(),
  )
}

///|
test "new Graph profile needs an explicit declaration and never borrows legacy SGA laws" {
  let requirements = operation_order_fixture(
    property_execution_steps(),
    property_graph=true,
  )
  let (checks, _, _) = program_sources_fixture(
    steps=Some(property_execution_steps()),
    property_graph=true,
  )
  let preparation = operation_profiles_preparation(checks)
  let legacy : PureOperationProfiles = {
    rela: true,
    sga: true,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  assert_true(
    check_operation_profiles(preparation, legacy, 10000000)
    is Err(UnsupportedProfile(_, _, _, @pipeline.PropertyGraph)),
  )
  assert_true(
    check_operation_profiles(
      preparation,
      { ..legacy, sga: false, },
      10000000,
      property_graph=true,
    )
    is Ok(_),
  )
  assert_true(operation_profiles_property_graph(checks))
  assert_true(!operation_profiles_declared(checks).sga)
  assert_true(
    prepare_program_checks(
      preparation_sources(preparation),
      { text_time: true, veca: false, },
      legacy,
      preparation_limits(),
      max_policy_depth=100,
      max_requirements=1000,
      max_regex_depth=100,
    )
    is Err(
      OperationProfiles(UnsupportedProfile(_, _, _, @pipeline.PropertyGraph))
    ),
  )
  let prepared = prepare_program_checks(
    preparation_sources(preparation),
    { text_time: true, veca: false, },
    { ..legacy, sga: false, },
    preparation_limits(),
    max_policy_depth=100,
    max_requirements=1000,
    max_regex_depth=100,
    property_graph=true,
  ).unwrap()
  assert_true(operation_profiles_property_graph(prepared))
  let profiles = resolution_profiles(requirements)
  assert_true(operation_profile_links_count(profiles) > 0)
  for i in 0..<operation_profile_links_count(profiles) {
    let resolution = operation_profile_links_at(profiles, i).unwrap()
    assert_eq(resolution.profile, @pipeline.PropertyGraph)
    assert_true(operation_profiles_property_graph(resolution.checks))
    assert_eq(operation_profile_adopted_law_count(resolution), 1)
    assert_eq(
      operation_profile_adopted_law_at(resolution, 0),
      Some(@pipeline.PropertyGraphLaw),
    )
    assert_true(operation_profile_adopted_law_at(resolution, 1) is None)
  }
}

///|
test "keyed construction index and contract inventory keep distinct law roots and exact scan budgets" {
  let requirements = operation_order_fixture(
    property_execution_steps(),
    property_graph=true,
    capacity_policy=property_execution_policy(),
    host_profile=property_execution_host_profile(),
  )
  let profiles = resolution_profiles(requirements)
  let indexed = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
  check_operation_closure(indexed)
  let mut checks = 0
  for i in 0..<operation_resolution_count(indexed) {
    if operation_resolution_at(indexed, i)
      is Some(Execution(PropertyGraphConstructionExecution(check))) {
      assert_eq(@pipeline.input_occurrence_count(check.step), 3)
      checks += 1
    }
  }
  assert_true(checks >= 4)
  let used = operation_resolution_work(indexed)
  assert_true(
    index_program_operation_resolutions(profiles, used, 1000) is Ok(_),
  )
  assert_true(
    index_program_operation_resolutions(profiles, used - 1, 1000)
    is Err(BudgetExceeded),
  )
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let inventory = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  let mut law_roots = 0
  let mut count_roots = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    match root.site {
      OperationLaw(stage, visit, step, _, _)
      | OperationGraphCountRules(stage, visit, step) =>
        if @pipeline.step_at(
            program_identity_producer_at(identity, stage, visit).unwrap(),
            step,
          ).unwrap().operation
          is @pipeline.PropertyGraphConstruction(..) {
          if root.site is OperationGraphCountRules(_, _, _) {
            assert_eq(root.body, PropertyGraphCountRules)
            count_roots += 1
          } else {
            assert_eq(root.body, AdoptedBody(@pipeline.PropertyGraphLaw))
            assert_eq(
              core_contract_cid(root.body),
              "sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc",
            )
            law_roots += 1
          }
        }
      _ => ()
    }
  }
  assert_true(law_roots > 0)
  assert_eq(count_roots, law_roots)
  assert_true(!stage_has_contract(inventory, 0, GraphCountRules))
  // The unchanged catalog grammar still depends on the legacy Graph law.
  // That dependency is not an operation-profile root for the new constructor;
  // the exact per-operation roots above select the distinct Property Graph
  // law and quantity contracts, never legacy GraphCountRules.
  assert_true(
    stage_has_contract(inventory, 0, AdoptedBody(@pipeline.SgaIdentity)),
  )
}
