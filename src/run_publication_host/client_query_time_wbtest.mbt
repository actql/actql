///|
fn client_query_time_test_request(
  owner : PreparedClientEffectComputation,
  name : String,
) -> ClientRequestIdentity {
  prepare_client_effect_request_identity(
    owner,
    "sha256:" + "c".repeat(64),
    name,
    client_effect_original_input_intent_cid(owner),
  ).unwrap()
}

///|
test "query time preparation binds the original Effect owner request and saved Run" {
  let (owner, allowed, definition) = original_effect_materials_fixture()
  let request = client_query_time_test_request(owner, "query")
  let (created, _) = @publication.run_definition_lifetime(definition).unwrap()
  let preparation = prepare_client_effect_query_time(owner, request, created).unwrap()
  let time = bind_client_effect_query_evaluation_time(
    preparation, owner, allowed, definition, request,
  ).unwrap()
  let run = bind_client_effect_compiled_run(owner, allowed, definition).unwrap()
  assert_true(client_effect_run_query_time_matches(run, preparation, request))
  let copied_request = client_query_time_test_request(owner, "query")
  assert_false(
    client_effect_run_query_time_matches(run, preparation, copied_request),
  )
  let (_, until) = @publication.run_definition_lifetime(definition).unwrap()
  let other_definition = issue_client_effect_run_definition(
    allowed, "scope", "another-query", created, until,
  ).unwrap()
  let other_run = bind_client_effect_compiled_run(
    owner, allowed, other_definition,
  ).unwrap()
  assert_false(
    client_effect_run_query_time_matches(other_run, preparation, request),
  )
  assert_eq(client_query_time_preparation_created_at(preparation), created)
  assert_true(
    @publication.query_evaluation_time_matches(
      time,
      allowed.admission,
      definition,
    ),
  )
  let restored = restore_client_effect_query_evaluation_time(
    owner, allowed, definition, request,
  ).unwrap()
  assert_true(
    @publication.query_evaluation_time_matches(
      restored,
      allowed.admission,
      definition,
    ),
  )
  match @publication.query_evaluation_time_value(restored).value {
    @values.Timestamp(value) => assert_eq(value, created)
    _ => fail("The saved original must remain Timestamp data")
  }
  let copy = client_query_time_test_request(owner, "query")
  assert_true(
    bind_client_effect_query_evaluation_time(
      preparation, owner, allowed, definition, copy,
    )
    is Err(ForeignRequest),
  )
  let different = client_query_time_test_request(owner, "other-query")
  assert_true(
    bind_client_effect_query_evaluation_time(
      preparation, owner, allowed, definition, different,
    )
    is Err(ForeignRequest),
  )
}

///|
test "query time preparation refuses replacement samples owners and Run definitions" {
  let (owner, allowed, definition) = original_effect_materials_fixture()
  let request = client_query_time_test_request(owner, "query")
  assert_true(
    prepare_client_effect_query_time(owner, request, "now")
    is Err(InvalidSample),
  )
  let wrong = prepare_client_effect_query_time(
    owner, request, "2026-10-09T00:00:01.000Z",
  ).unwrap()
  assert_true(
    bind_client_effect_query_evaluation_time(
      wrong, owner, allowed, definition, request,
    )
    is Err(ForeignRun),
  )
  let (created, until) = @publication.run_definition_lifetime(definition).unwrap()
  let preparation = prepare_client_effect_query_time(owner, request, created).unwrap()
  let (foreign, foreign_allowed, _) = original_effect_materials_fixture()
  assert_true(
    bind_client_effect_query_evaluation_time(
      preparation, foreign, foreign_allowed, definition, request,
    )
    is Err(ForeignPreparation),
  )
  assert_true(
    bind_client_effect_query_evaluation_time(
      preparation, owner, foreign_allowed, definition, request,
    )
    is Err(ForeignRun),
  )
  bind_client_effect_query_evaluation_time(
    preparation, owner, allowed, definition, request,
  ).unwrap()
  |> ignore
  let other = issue_client_effect_run_definition(
    allowed, "scope", "other-query", created, until,
  ).unwrap()
  assert_true(
    bind_client_effect_query_evaluation_time(
      preparation, owner, allowed, other, request,
    )
    is Err(ForeignRun),
  )
}

///|
// Independent Node crypto ordering of the original complete fixture members;
// only their required evidence order and enclosing self identity differ.
let client_query_time_source_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b","sha256:db7ce19477afd82a8488a9f64fd75697c850eaaccdc738995483cc138a06361a"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"},{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b","sha256:db7ce19477afd82a8488a9f64fd75697c850eaaccdc738995483cc138a06361a"],"read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"}],"connector_catalogs":[{"catalog_cid":"sha256:b256d9e2361b791cc2df19e1f87f9d53feb0616c539f07dd62e8bc566259e162","commands":[],"connector_id":"crm/right","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm/main","connector_id":"crm/main","connector_version":"fixture"},{"connector":"crm/right","connector_id":"crm/right","connector_version":"fixture"},{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:9882e5f1412beaf650b0fdaf55035b198b7b87e8e9e3c3a0f07730953b0a72ed","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:f298b9a108471ac14005fa6146e6499213826bad153c16b4dab9ae60d0aad8ab","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:create"],"selector_class":"none","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"},{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_data_policy_cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
fn client_query_time_source_fixture() -> (
  PreparedClientEffectComputation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
) raise {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let environment = admit_client_check_environment(
    client_query_time_source_environment,
    "sha256:9882e5f1412beaf650b0fdaf55035b198b7b87e8e9e3c3a0f07730953b0a72ed",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document = bound_effect_source_document.replace(
    old="{\"gte\":[{\"field\":\"id\"},{\"literal\":0}]}",
    new="\"current_timestamp() = current_timestamp()\"",
  )
  assert_true(document != bound_effect_source_document)
  let owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let bounds = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "scope", "query-source", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  (owner, allowed, definition)
}

///|
fn client_query_time_expression_value(
  expression : @lower.Expression,
  context : @publication.QueryEvaluationTime,
) -> @execution.Value raise {
  let running = @execution.start_expression_execution(
    expression,
    Map([]),
    [],
    10000,
    64,
    64,
    query_time=Some(context),
  ).unwrap()
  for _ in 0..<10000 {
    match @execution.advance_expression_execution(running).unwrap() {
      @execution.ExpressionContinue => ()
      @execution.ExpressionComplete(value) => return value
    }
  }
  @execution.cancel_expression_execution(running) |> ignore
  fail("The bounded query-time expression did not terminate")
}

///|
test "query time acquisition retains its dependency until the same original Run is bound" {
  let (owner, allowed, definition) = client_query_time_source_fixture()
  let request = client_query_time_test_request(owner, "query-source")
  let wrong_source = prepare_client_effect_request_identity(
    owner,
    "sha256:" + "c".repeat(64),
    "query-source",
    "sha256:" + "0".repeat(64),
  ).unwrap()
  assert_true(
    prepare_client_effect_query_time(
      owner, wrong_source, "2026-10-09T00:00:00.000Z",
    )
    is Err(ForeignRequest),
  )
  let preparation = prepare_client_effect_query_time(
    owner, request, "2026-10-09T00:00:00.000Z",
  ).unwrap()
  let shape = prepare_client_query_acquisition_shape(
    client_effect_program_view(owner),
    0,
    0,
  ).unwrap()
  assert_true(@acquisition.query_acquisition_query_time_required(shape))
  assert_true(@acquisition.query_acquisition_query_time(shape) is None)
  assert_true(
    prepare_client_effect_query_acquisition(owner, 0, 0)
    is Err(UnsupportedAcquisition(@acquisition.UnboundRequest)),
  )
  assert_true(
    prepare_client_effect_query_acquisition_at_query_time(
      owner, 0, 0, preparation, request,
    )
    is Err(UnsupportedAcquisition(@acquisition.UnboundRequest)),
  )
  let context = bind_client_effect_query_evaluation_time(
    preparation, owner, allowed, definition, request,
  ).unwrap()
  let acquisition = prepare_client_effect_query_acquisition_at_query_time(
    owner, 0, 0, preparation, request,
  ).unwrap()
  assert_true(@acquisition.query_acquisition_query_time_required(acquisition))
  assert_true(
    @acquisition.query_acquisition_query_time(acquisition) is Some(original) &&
    physical_equal(original, context),
  )
  let repeated = bind_client_effect_query_evaluation_time(
    preparation, owner, allowed, definition, request,
  ).unwrap()
  assert_true(physical_equal(repeated, context))
  let assets = client_local_product_assets()
  let contracts = @local_query_time.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let local_requirement = @local_query_time.prepare_effect_local_query_requirement_at_query_time(
    owner,
    0,
    0,
    preparation,
    request,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let local_query = @query.query_sequence_requirement(
    @planning.query_material_owner(
      @planning.query_requirement_material(local_requirement),
    ),
  )
  let original_wire = @encode.document_text(
    @planning.query_requirement_document(local_requirement),
  )
  assert_true(
    original_wire.contains(
      "\"run_definition_cid\":\"" +
      @publication.publication_contract_identity(definition) +
      "\"",
    ),
  )
  let (_, until) = @publication.run_definition_lifetime(definition).unwrap()
  let other_definition = issue_client_effect_run_definition(
    allowed, "scope", "another-query-source", "2026-10-09T00:00:00.000Z", until,
  ).unwrap()
  let other_request = client_query_time_test_request(
    owner, "another-query-source",
  )
  let other_preparation = restore_client_effect_query_time_preparation(
    owner, allowed, other_definition, other_request,
  ).unwrap()
  let other_requirement = @local_query_time.prepare_effect_local_query_requirement_at_query_time(
    owner,
    0,
    0,
    other_preparation,
    other_request,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(
    @planning.query_requirement_cid(local_requirement) !=
    @planning.query_requirement_cid(other_requirement),
  )
  assert_eq(
    @planning.query_material_cids(
      @planning.query_requirement_material(local_requirement),
    ),
    @planning.query_material_cids(
      @planning.query_requirement_material(other_requirement),
    ),
  )
  assert_true(
    @acquisition.query_acquisition_query_time(local_query) is Some(original) &&
    physical_equal(original, context),
  )
  assert_true(
    @local_query_time.prepare_effect_local_query_requirement_at_query_time(
      owner,
      0,
      0,
      preparation,
      client_query_time_test_request(owner, "query-source"),
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Err(@local_query_time.Sequences),
  )
  let sequences = @local_query_time.prepare_client_effect_local_sequences_at_query_time(
    owner,
    preparation,
    request,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(sequences.length() > 0)
  assert_true(
    @execution.generated_sequence_query_time(sequences[0]) is Some(original) &&
    physical_equal(original, context),
  )
  let requirement = prepare_client_effect_query_requirement_at_query_time(
    owner,
    sequences[0],
    0,
    0,
    preparation,
    request,
    { max_rows: 100, max_value_bytes: 10000, },
    {
      max_work: 1000000,
      max_fields: 100,
      max_parameters: 100,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  assert_true(
    physical_equal(
      @planning.query_requirement_program(requirement),
      @checked.source_identity(
        @strategy.graph_program(
          @strategy.checked_effect_computation_graph(owner.graph),
        ),
      ),
    ),
  )
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let task = @strategy.graph_task_owner(graph, 0).unwrap()
  let predicate = @lower.lower_expression(task, 0, 0, {
    max_nodes: 10000,
    max_work: 100000,
    max_depth: 100,
    max_literal_nodes: 10000,
    max_literal_text_bytes: 100000,
  }).unwrap()
  guard @lower.expression_body(predicate) is @lower.Binary(_, expression, _) else {
    fail(
      "The original checked predicate must retain both current-time occurrences",
    )
  }
  for _ in 0..<3 {
    assert_true(
      client_query_time_expression_value(expression, context)
      is @execution.Captured(@values.Timestamp("2026-10-09T00:00:00.000Z")),
    )
  }
  let restored = restore_client_effect_query_evaluation_time(
    owner, allowed, definition, request,
  ).unwrap()
  assert_true(
    client_query_time_expression_value(expression, restored)
    is @execution.Captured(@values.Timestamp("2026-10-09T00:00:00.000Z")),
  )
  let foreign_request = client_query_time_test_request(owner, "other-source")
  assert_true(
    prepare_client_effect_query_acquisition_at_query_time(
      owner, 0, 0, preparation, foreign_request,
    )
    is Err(UnsupportedAcquisition(@acquisition.UnboundRequest)),
  )
  let (foreign_owner, _, _) = client_query_time_source_fixture()
  assert_true(
    prepare_client_effect_query_acquisition_at_query_time(
      foreign_owner, 0, 0, preparation, request,
    )
    is Err(UnsupportedAcquisition(@acquisition.UnboundRequest)),
  )
}
