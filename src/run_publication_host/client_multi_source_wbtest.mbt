///|
// Independently authored two-source machine Program and pinned Catalog bytes.
// The expected effective-policy CID is a SHA-256 of its canonical contract
// preimage, computed independently of the common checker and bridge.
let multi_source_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"},{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"connector_catalogs":[{"catalog_cid":"sha256:b256d9e2361b791cc2df19e1f87f9d53feb0616c539f07dd62e8bc566259e162","commands":[],"connector_id":"crm/right","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:c9cf17f3e181c97a69e3419d4543e98c9a04af6da9490b359511a673a64c49a7","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":4096,"max_replacements":4096,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"},{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_data_policy_cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
let multi_source_program : String =
  #|{"id":"fixture.two-independent-duckdb-join","results":{"joined":{"from":{"result":"rows","stage":"join_sources"}}},"stages":[{"id":"acquire_left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"rows":{"fields":["id","amount"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id >= 0"},{"as":"captured","select":["id","amount"]}]},{"id":"acquire_right","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"results":{"rows":{"fields":["id","amount"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id >= 0"},{"as":"captured","select":["id","amount"]}]},{"id":"join_sources","inputs":{"left_rows":{"result":{"result":"rows","stage":"acquire_left"}},"right_rows":{"result":{"result":"rows","stage":"acquire_right"}}},"results":{"rows":{"fields":["id","left_amount","right_amount"],"from":"ordered"}},"steps":[{"from":"left_rows","join":{"kind":"inner","max_output_rows":100,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","left_amount":"left.amount","right_amount":"right.amount"},"with":"right_rows"}},{"as":"ordered","sort":[{"id":"asc"},{"left_amount":"asc"},{"right_amount":"asc"}]}]}],"version":"actql/0.1"}

///|
fn multi_source_prepared(document : String) -> PreparedClientProgram raise {
  let environment = admit_client_check_environment(
    multi_source_environment,
    "sha256:c9cf17f3e181c97a69e3419d4543e98c9a04af6da9490b359511a673a64c49a7",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  match
    prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Graph(UnsupportedIncoming(index))) =>
      fail("unsupported incoming " + index.to_string())
    Err(Graph(MissingProducer(stage, input))) =>
      fail("missing producer " + stage.to_string() + ":" + input.to_string())
    Err(Graph(_)) => fail("another graph issue")
    Err(Syntax(_)) => fail("syntax issue")
    Err(Check(_)) => fail("check issue")
    Err(_) => fail("another preparation issue")
  }
}

///|
test "operation selection is not completion or borrowed output authority" {
  let prepared = multi_source_prepared(multi_source_program)
  let graph = prepared.graph
  // Stage 0 is an acquired filter/select sequence. Its filter exists, but is
  // not the completed output handed to the following computation.
  assert_eq(@strategy.graph_stage_operation_task(graph, 0, 0), Some(0))
  assert_eq(
    @strategy.graph_stage_target_task(graph, 0, @pipeline.Step(0)),
    None,
  )
  // Stage 2's JOIN is inside an ordinary Relation sequence followed by sort
  // and Result projection. Resolving its owner does not publish an early JOIN.
  assert_eq(@strategy.graph_stage_operation_task(graph, 2, 0), Some(2))
  assert_eq(
    @strategy.graph_stage_target_task(graph, 2, @pipeline.Step(0)),
    None,
  )
  assert_eq(@strategy.graph_stage_operation_task(graph, 2, -1), None)
  assert_eq(@strategy.graph_stage_operation_task(graph, 2, 99), None)
  assert_eq(@strategy.graph_stage_operation_task(graph, -1, 0), None)
  assert_eq(@strategy.graph_stage_operation_task(graph, 99, 0), None)
}

///|
test "two acquired tasks resolve the exact joined Result policy" {
  let prepared = multi_source_prepared(multi_source_program)
  assert_eq(prepared_client_acquisition_count(prepared), 2)
  assert_eq(prepared_client_result_count(prepared), 1)
  assert_eq(prepared_client_result_name(prepared, 0), Some("joined"))
  assert_eq(
    prepared_client_publication_data_policy_cid(prepared),
    Some(
      "sha256:bfb29a3ad6c5f1f3e72e2a59b17ee8df772f88fa8b37ee0f958d6b07cb20c670",
    ),
  )
  // The first source policy is never a substitute for the checked join.
  assert_true(
    prepared_client_publication_data_policy_cid(prepared) !=
    Some(
      "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
    ),
  )
}

///|
test "publication policy follows exact final aliases and rejects partial coverage" {
  let aliased = multi_source_prepared(
    multi_source_program.replace(
      old="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"join_sources\"}}",
      new="\"renamed\":{\"from\":{\"result\":\"rows\",\"stage\":\"join_sources\"}}",
    ),
  )
  assert_eq(prepared_client_result_name(aliased, 0), Some("renamed"))
  assert_eq(
    prepared_client_publication_data_policy_cid(aliased),
    Some(
      "sha256:bfb29a3ad6c5f1f3e72e2a59b17ee8df772f88fa8b37ee0f958d6b07cb20c670",
    ),
  )
  let partial = multi_source_prepared(
    multi_source_program.replace(
      old="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"join_sources\"}}",
      new="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"acquire_left\"}}",
    ),
  )
  assert_eq(prepared_client_acquisition_count(partial), 2)
  assert_eq(prepared_client_publication_data_policy_cid(partial), None)
}

///|
test "two-source observation keeps both task ordered evidence CIDs" {
  let prepared = multi_source_prepared(multi_source_program)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let sources = ["sha256:" + "a".repeat(64), "sha256:" + "b".repeat(64)]
  let (observation, _) = issue_client_captured_observation_from_template(
    client_task_compilation_template(compilation),
    sources,
    prepared_client_publication_data_policy_cid(prepared).unwrap(),
    "2026-10-02T00:00:00.000Z",
    "2026-10-02T00:00:01.000Z",
    100000,
    10000,
    100,
  ).unwrap()
  let body = parse_plan_identity_value(
    @publication.run_evidence_value_json(observation),
    100000,
    10000,
    100,
  ).unwrap()
  guard @canonical.object_field(body, "source_evidence_cids")
    is Some(@canonical.Array(values)) else {
    fail("missing complete Source Evidence inventory")
  }
  let listed = @canonical.array_values(values)
  assert_eq(listed.length(), 2)
  for task in 0..<2 {
    guard listed[task] is @canonical.String(cid) else {
      fail("source evidence CID is not a string")
    }
    assert_eq(cid, sources[task])
  }
}

///|
test "whole Run policy covers same original responses and refuses equal foreign or missing coverage" {
  let prepared = multi_source_prepared(multi_source_program)
  let program = @strategy.graph_program(prepared.graph)
  let policy = @checked.publication_source_policy(
    @checked.unit_publication_at(program, 2, 0).unwrap(),
  ).unwrap()
  assert_true(
    client_publication_policy_covers_source_responses(program, policy),
  )
  let foreign = multi_source_prepared(multi_source_program)
  let foreign_program = @strategy.graph_program(foreign.graph)
  let foreign_policy = @checked.publication_source_policy(
    @checked.unit_publication_at(foreign_program, 2, 0).unwrap(),
  ).unwrap()
  assert_eq(policy.cid, foreign_policy.cid)
  assert_false(
    client_publication_policy_covers_source_responses(program, foreign_policy),
  )
  assert_false(
    client_publication_policy_covers_source_responses(foreign_program, policy),
  )
  let partial = multi_source_prepared(
    multi_source_program.replace(
      old="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"join_sources\"}}",
      new="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"acquire_left\"}}",
    ),
  )
  let partial_program = @strategy.graph_program(partial.graph)
  let partial_policy = @checked.publication_source_policy(
    @checked.unit_publication_at(partial_program, 0, 0).unwrap(),
  ).unwrap()
  assert_eq(@checked.publication_policy_source_count(partial_policy), 1)
  assert_false(
    client_publication_policy_covers_source_responses(
      partial_program, partial_policy,
    ),
  )
}
