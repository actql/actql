///|
// Exact existing independent update-Source vector, not generated from this
// caller. Resource/physical owner-ACK ports below are explicit stand-ins;
// these cases allocate no actual VM, Account, durable state or provider read.
let funded_request_source_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"},{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"connector_catalogs":[{"catalog_cid":"sha256:b256d9e2361b791cc2df19e1f87f9d53feb0616c539f07dd62e8bc566259e162","commands":[],"connector_id":"crm/right","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm/main","connector_id":"crm/main","connector_version":"fixture"},{"connector":"crm/right","connector_id":"crm/right","connector_version":"fixture"},{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:aeb50e7260b47a2a152ee593bac2956835f53570c6c5fc68b5caf39c1da3959e","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:275614ef615205a8e8eef3cdd1f15f5ef28b25fa90332600fc816def40eb2c58","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"number"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:c000fb12383456a0e123e74501d164b96bb886251dbb44f301661070321be8e0","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"},{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_data_policy_cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
fn funded_request_source_environment() -> (
  @checked.CheckEnvironment,
  String,
  @source_publication.PreparedPublishedQueryEnvironment,
) {
  let environment = @publication_host.admit_client_check_environment(
    funded_request_source_environment_wire,
    "sha256:aeb50e7260b47a2a152ee593bac2956835f53570c6c5fc68b5caf39c1da3959e",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"crm.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"installationOwnerCid\":\"sha256:" +
    "e".repeat(64) +
    "\"}]}"
  (
    environment,
    publication,
    @source_publication.prepare_published_query_environment(
      environment, publication,
    ).unwrap(),
  )
}

///|
fn funded_request_source_parent(
  wire : String,
  limits? : @resources.LedgerLimits? = None,
) -> (
  @resources.Ledger,
  @resources.BackedExecutionLiveAccess[Ref[Int], Ref[Int], Array[Int]],
  @resources.BackedPreparationAdmission[Array[Int]],
  ClientRequestPreparation[Array[Int]],
  Array[Int],
) {
  let limits = limits.unwrap_or(
    client_local_preparation_initial_limits(client_local_resource_policy()).unwrap(),
  )
  let (root, access, initial, input) = backed_request_initial_fixture(limits)
  let parent = begin_backed_request_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  let intent = @publication_host.prepare_client_submitted_intent(
    wire, 65536, 8192, 64,
  ).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  (root, access, initial, parent, input)
}

///|
let funded_request_source_pure_wire : String =
  #|{"kind":"aql","input":{"format":"sql","text":"SELECT @n AS n","parameterDeclarations":{"n":{"type":"number"}}},"parameters":{"n":7}}

///|
fn compile_funded_request_source(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  environment : @checked.CheckEnvironment,
  publication : String,
  selected : @source_publication.PreparedPublishedQueryEnvironment,
) -> Unit {
  prepare_request_source_input(parent, input, environment, publication).unwrap()
  let (text, format, declarations, _) = request_source_input_parts(
    parent, input,
  ).unwrap()
  parse_request_query_syntax(parent, input, text, format).unwrap() |> ignore
  lower_request_published_query(
    parent,
    input,
    selected,
    environment,
    declarations,
    public_primary=true,
  ).unwrap()
  |> ignore
  prepare_request_original_computation_check(
    parent,
    input,
    environment,
    selected,
    [],
    @publication_host.client_standard_program_preparation_limits(),
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  finish_request_checked_computation(parent, input, environment, selected).unwrap()
  |> ignore
}

///|
fn close_funded_request_source(
  access : @resources.BackedExecutionLiveAccess[Ref[Int], Ref[Int], Array[Int]],
  initial : @resources.BackedPreparationAdmission[Array[Int]],
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
) -> Unit raise {
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(Initial(_)),
  )
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.phase == Closed)
}

///|
test "funded Source Request keeps same Parameter compiler and borrower through actual pending retirement" {
  let (_, access, initial, parent, input) = funded_request_source_parent(
    funded_request_source_pure_wire,
  )
  let (environment, publication, selected) = funded_request_source_environment()
  compile_funded_request_source(
    parent, input, environment, publication, selected,
  )
  let prepared = parent.compiled_program.unwrap()
  let capacity = parent.program_capacity.unwrap()
  let origin = request_source_input_original(parent).unwrap()
  let holder = borrow_request_source_preparation(parent, input).unwrap()
  let source = @resources.preparation_body_borrow_value(holder).unwrap()
  assert_true(
    @publication_host.client_source_computation_preparation(source)
    is Pure(original) &&
    physical_equal(original, prepared),
  )
  assert_true(physical_equal(capacity, parent.program_capacity.unwrap()))
  assert_eq(
    @publication_host.client_source_computation_material(source).1,
    Some("{\"n\":7}"),
  )
  assert_eq(
    @publication_host.client_source_computation_source(source).0,
    "SELECT @n AS n",
  )
  let quote = parent.source_input.unwrap().handoff_quote.unwrap()
  let second = borrow_request_source_preparation(parent, input).unwrap()
  assert_true(
    physical_equal(
      source,
      @resources.preparation_body_borrow_value(second).unwrap(),
    ),
  )
  assert_eq(parent.source_input.unwrap().handoff_quote.unwrap(), quote)
  @resources.return_preparation_body_borrow(second).unwrap() |> ignore
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(parent.phase == Retiring && parent.source_input is None)
  assert_true(@publication_host.client_source_input_parts(origin) is Err(Input))
  assert_true(
    @resources.preparation_body_borrow_value(holder) is Some(original) &&
    physical_equal(original, source),
  )
  assert_true(@resources.ledger_usage(parent.ledger).live_reservations > 0)
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  close_funded_request_source(access, initial, parent, input)
  assert_true(@resources.preparation_body_borrow_value(holder) is None)
}

///|
test "funded Source Request transfers same Source compiler to actual Run and keeps borrower fence" {
  let (_, access, initial, parent, input) = funded_request_source_parent(
    funded_request_source_pure_wire,
  )
  let (environment, publication, selected) = funded_request_source_environment()
  compile_funded_request_source(
    parent, input, environment, publication, selected,
  )
  let prepared = parent.compiled_program.unwrap()
  let source_holder = borrow_request_source_preparation(parent, input).unwrap()
  let source = @resources.preparation_body_borrow_value(source_holder).unwrap()
  let origin = request_source_input_original(parent).unwrap()
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let request = @publication_host.client_source_computation_request(
    source,
    "sha256:" + "a".repeat(64),
    "same-original-source-request",
  ).unwrap()
  assert_eq(
    @publication_host.client_request_input_cid(request),
    @publication_host.client_submitted_intent_cid(
      parent.submitted_intent.unwrap(),
    ),
  )
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(parent.phase == Selected && parent.source_input is None)
  assert_true(@publication_host.client_source_input_parts(origin) is Err(Input))
  assert_true(
    installed_managed_run_compilation_original(run, prepared) is Some(_),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @resources.preparation_body_borrow_value(source_holder) is Some(original) &&
    physical_equal(original, source),
  )
  @resources.return_preparation_body_borrow(source_holder).unwrap() |> ignore
  assert_true(retire_installed_managed_run(run) is Err(Resource(Unavailable)))
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  retire_installed_managed_run(run).unwrap()
}

///|
test "funded Source Request Effect constructor keeps SAME nonnull Parameter and original Source association" {
  let (_, access, initial, parent, input) = funded_request_source_parent(
    (
      #|{"kind":"aql","input":{"format":"sql","text":"SELECT 1 AS id, @n AS value |> RESULT out |> EFFECT UPDATE crm.Account ID id SET (Name = value)","parameterDeclarations":{"n":{"type":"number"}}},"parameters":{"n":2}}
    ),
  )
  let (environment, publication, selected) = funded_request_source_environment()
  compile_funded_request_source(
    parent, input, environment, publication, selected,
  )
  assert_true(parent.phase == EffectCompiled && parent.program_capacity is None)
  let prepared = parent.compiled_effect.unwrap()
  let holder = borrow_request_source_preparation(parent, input).unwrap()
  let source = @resources.preparation_body_borrow_value(holder).unwrap()
  assert_true(
    @publication_host.client_source_computation_preparation(source)
    is Effect(original) &&
    physical_equal(original, prepared),
  )
  assert_eq(
    @publication_host.client_source_computation_material(source).1,
    Some("{\"n\":2}"),
  )
  let request = @publication_host.client_source_computation_request(
    source,
    "sha256:" + "a".repeat(64),
    "same-original-effect-source-request",
  ).unwrap()
  assert_eq(
    @publication_host.client_request_input_cid(request),
    @publication_host.client_submitted_intent_cid(
      parent.submitted_intent.unwrap(),
    ),
  )
  assert_true(
    borrow_request_source_preparation(parent, [3]) is Err(ForeignOriginal),
  )
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  close_funded_request_source(access, initial, parent, input)
}

///|
test "funded Source Request one-short intake refuses before constructor and cannot take legacy parse path" {
  let (_, access, initial, first, input) = funded_request_source_parent(
    funded_request_source_pure_wire,
  )
  let (r, e) = @resources.preparation_capacity_working_extents(
    first.capacity,
    input,
  ).unwrap()
  let bytes = request_source_input_construction_bytes(first).unwrap()
  let limits = {
    ..client_local_preparation_initial_limits(client_local_resource_policy()).unwrap(),
    retained_bytes: r + bytes - 1L,
    execution_bytes: e + bytes,
  }
  close_funded_request_source(access, initial, first, input)
  let (_, access, initial, parent, input) = funded_request_source_parent(
    funded_request_source_pure_wire,
    limits=Some(limits),
  )
  let (environment, publication, _) = funded_request_source_environment()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_source_input(parent, input, environment, publication)
    is Err(Capacity(_)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  let context = parent.source_input.unwrap()
  assert_false(context.attempted)
  assert_true(context.outcome is None && parent.query_syntax is None)
  assert_true(
    parse_request_query_syntax(parent, input, "SELECT 7 AS n", @frontend.Sql)
    is Err(Request(ForeignOriginal)),
  )
  assert_true(parent.query_syntax is None)
  close_funded_request_source(access, initial, parent, input)
}

///|
test "funded Source Request failed parser retains original prefix and child until real retirement" {
  let (_, access, initial, parent, input) = funded_request_source_parent(
    (
      #|{"kind":"aql","input":{"format":"sql","text":"SELECT ("},"parameters":null}
    ),
  )
  let (environment, publication, _) = funded_request_source_environment()
  prepare_request_source_input(parent, input, environment, publication).unwrap()
  let context = parent.source_input.unwrap()
  let source = request_source_input_original(parent).unwrap()
  let (text, format, _, _) = request_source_input_parts(parent, input).unwrap()
  assert_true(
    parse_request_query_syntax(parent, input, text, format) is Err(Frontend(_)),
  )
  assert_true(parent.phase == QuerySyntaxFailed)
  let (known, _) = request_query_syntax_work(parent, input).unwrap()
  assert_true(known > 0L)
  assert_true(physical_equal(context, parent.source_input.unwrap()))
  assert_true(
    context.attempted &&
    context.outcome is Some(Ok(original)) &&
    physical_equal(original, source),
  )
  assert_true(
    prepare_request_source_input(parent, input, environment, publication)
    is Err(WrongPhase),
  )
  assert_true(
    borrow_request_source_preparation(parent, input) is Err(WrongPhase),
  )
  assert_true(@resources.ledger_usage(parent.ledger).live_reservations > 0)
  close_funded_request_source(access, initial, parent, input)
  assert_true(@publication_host.client_source_input_parts(source) is Err(Input))
  assert_true(parent.source_input is None)
}

///|
// SAME ordinary funded Source Request and typed terminal used by the installed
// caller. No Provider, Run or durable state is entered by this regression.
test "funded Source terminal refuses resolved nested ARRAY before body consumer" {
  for format in ["sql", "aql-text"] {
    let wire = "{\"kind\":\"aql\",\"input\":{\"format\":\"" +
      format +
      "\",\"text\":\"SELECT [[1,2]] AS value\"},\"parameters\":null}"
    let (_, access, initial, parent, input) = funded_request_source_parent(wire)
    let (environment, publication, selected) = funded_request_source_environment()
    prepare_request_source_input(parent, input, environment, publication).unwrap()
    let (text, actual_format, declarations, _) = request_source_input_parts(
      parent, input,
    ).unwrap()
    parse_request_query_syntax(parent, input, text, actual_format).unwrap()
    |> ignore
    lower_request_published_query(
      parent,
      input,
      selected,
      environment,
      declarations,
      public_primary=true,
    ).unwrap()
    |> ignore
    prepare_request_original_computation_check(
      parent,
      input,
      environment,
      selected,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    let original = parent.held_program.unwrap()
    guard finish_request_checked_computation(
        parent, input, environment, selected,
      )
      is Err(
        Preparation(SourceInput(Source(@publication_host.ArrayProfile(_))))
      ) else {
      fail("funded Source terminal skipped checked ARRAY profile: " + format)
    }
    assert_true(
      parent.compiled_program is Some(prepared) &&
      physical_equal(
        @checked.checked_source_program(
          @strategy.graph_program(
            @publication_host.prepared_client_graph(prepared),
          ),
        ),
        original,
      ),
    )
    close_funded_request_source(access, initial, parent, input)
  }
}

///|
test "funded Source terminal preserves flat ARRAY and same cached original after profile" {
  let wire = "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT [1,2] AS value\"},\"parameters\":null}"
  let (_, access, initial, parent, input) = funded_request_source_parent(wire)
  let (environment, publication, selected) = funded_request_source_environment()
  compile_funded_request_source(parent, input, environment, publication, selected)
  let prepared = parent.compiled_program.unwrap()
  let first = borrow_request_source_preparation(parent, input).unwrap()
  let original = @resources.preparation_body_borrow_value(first).unwrap()
  assert_true(@publication_host.client_source_computation_preparation(original) is Pure(actual) && physical_equal(actual, prepared))
  @resources.return_preparation_body_borrow(first).unwrap() |> ignore
  let second = borrow_request_source_preparation(parent, input).unwrap()
  assert_true(physical_equal(@resources.preparation_body_borrow_value(second).unwrap(), original))
  @resources.return_preparation_body_borrow(second).unwrap() |> ignore
  close_funded_request_source(access, initial, parent, input)
}
