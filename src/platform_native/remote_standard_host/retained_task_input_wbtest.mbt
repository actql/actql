///|
// Reuse the existing Source contract fixture; no connection settings enter it.
let retained_transfer_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89","sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8"],"read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"},{"capability_contract_cids":["sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89","sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"connector_catalogs":[{"catalog_cid":"sha256:b256d9e2361b791cc2df19e1f87f9d53feb0616c539f07dd62e8bc566259e162","commands":[],"connector_id":"crm/right","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:4cfc3a08514b254c76ac810df9153072a3f0edbf0f211c18b85298aa0c51a92e","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"},{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_data_policy_cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
let retained_transfer_program : String =
  #|{"version":"actql/0.1","id":"retained-source-compute","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id > 2","as":"filtered"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"rows"}}}}

///|
fn retained_transfer_run() -> (
  @publication_host.PreparedClientProgram,
  @publication_host.ClientTaskCompilation,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
) {
  let environment = @publication_host.admit_client_check_environment(
    retained_transfer_environment,
    "sha256:4cfc3a08514b254c76ac810df9153072a3f0edbf0f211c18b85298aa0c51a92e",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    retained_transfer_program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    standard_transfer_input_cid("a"),
    standard_transfer_input_cid("b"),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    allowed, "retained-scope", "run-a", "2026-10-05T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (prepared, compilation, allowed, definition)
}

///|
fn retained_transfer_edge() -> @publication_host.ClientRetainedInputEdge {
  let (prepared, compilation, allowed, definition) = retained_transfer_run()
  @publication_host.prepare_client_retained_input_edge(
    prepared,
    compilation,
    @publication_host.client_compiled_run_admission(allowed),
    definition,
    1,
    0,
  ).unwrap()
}

///|
fn retained_transfer_fixture(
  committed : Bool,
  edge? : @publication_host.ClientRetainedInputEdge? = None,
  release? : Ref[(() -> Unit)?]? = None,
) -> (
  @publication_host.ClientRetainedInputProducer,
  @transfer.RemoteTransferRecord,
  @transfer.RemoteTransferDestinationReceipt,
  @site.ExecutionSite,
) {
  let edge = edge.unwrap_or_else(retained_transfer_edge)
  let ports = @publication_host.client_retained_input_edge_projection(edge)
  let chunk = b"{\"id\":3}"
  let physical = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    @publication_host.client_retained_input_edge_schema_cid(edge),
    standard_transfer_input_cid("7"),
    standard_transfer_input_cid("8"),
    1,
    ["sha256:" + @sha.hex(chunk)],
    [8L],
    [1],
    8,
    4096,
    8L,
  ).unwrap()
  // Protocol owner fixture, not evidence of Source execution or physical I/O.
  let request = @remote.prepare_dispatch_request(
    standard_transfer_input_cid("c"),
    ports[0],
    ports[1],
    1,
    "producer-dispatch",
    "site-a",
    1,
    standard_transfer_input_cid("a"),
    "local",
    "local/1",
    "strategy/1",
    standard_transfer_input_cid("1"),
    standard_transfer_input_cid("2"),
    standard_transfer_input_cid("3"),
    standard_transfer_input_cid("4"),
    standard_transfer_input_cid("5"),
  ).unwrap()
  let site = @site.create_site(
    "site-a",
    1,
    standard_transfer_input_cid("a"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let record = @remote.commit_dispatch_acceptance(
      @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
      true,
    ).unwrap().1
  let holding = @remote.remote_output_holding_evidence_cid(
    request, "producer-material", 8L,
  ).unwrap()
  @remote.restore_dispatch_record(
    record, 4, 3, 1, 0, true, false, "producer-material", holding, "",
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "producer-material",
    holding,
    standard_transfer_input_cid("6"),
    @publication_host.client_retained_input_edge_schema_cid(edge),
    physical.view_contract_cid,
    physical.codec_contract_cid,
    physical.manifest_cid,
    standard_transfer_input_cid("b"),
    1,
    8L,
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    standard_transfer_input_cid("a"),
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_managed_output_evidence_kind(),
    standard_transfer_input_cid("4"),
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_durable_execution_evidence(record, evidence).unwrap(),
    true,
  ).unwrap()
  if release is Some(callback) {
    callback.val = Some(() => {
      @remote.commit_dispatch_transition(
        @remote.prepare_begin_remote_release(record).unwrap(),
        true,
      ).unwrap()
    })
  }
  let producer = @publication_host.prepare_client_retained_input_producer(
    edge, record, evidence, subject,
  ).unwrap()
  let request = @transfer.prepare_request(
    standard_transfer_input_cid("c"),
    "transfer-a",
    @transfer.TransferStore,
    "site-a",
    1,
    "site-a",
    1,
    "producer-material",
    physical,
    8L,
    4102444800000L,
    standard_transfer_input_cid("4"),
    standard_transfer_input_cid("5"),
    standard_transfer_input_cid("6"),
  ).unwrap()
  let transfer = @transfer.open_record(request)
  if committed {
    ignore(
      @transfer.commit_transition(
        @transfer.prepare_start(transfer).unwrap(),
        true,
      ).unwrap(),
    )
    ignore(
      @transfer.commit_transition(
        @transfer.prepare_source_settled(transfer, true, true).unwrap(),
        true,
      ).unwrap(),
    )
    ignore(
      @transfer.commit_transition(
        @transfer.prepare_destination_commit(transfer).unwrap(),
        true,
      ).unwrap(),
    )
  }
  let receipt = @transfer.prepare_destination_receipt(
    request, "destination-material",
  ).unwrap()
  (producer, transfer, receipt, site)
}

///|
fn retained_transfer_current(
  site : @site.ExecutionSite,
  authority : String,
) -> NativeRemoteRetainedInputCurrent {
  install_native_remote_retained_input_current(
    () => site,
    () => authority,
    () => 1791158400000L,
    (_, _) => true,
  )
}

///|
test "retained Transfer preflight checks current grants without asserting receiver commit" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(false)
  let request = @transfer.record_request(transfer)
  let authorized = Ref(true)
  let current = @publication_host.install_client_retained_input_current(
    () => site,
    () => standard_transfer_input_cid("c"),
    () => 1791158400000L,
    (_, _) => authorized.val,
  )
  @publication_host.validate_client_retained_input_transfer_current(
    producer, request, current,
  ).unwrap()
  // Request admission must not loosen the existing binding commit boundary.
  assert_true(
    @publication_host.prepare_client_retained_task_input(
      producer, transfer, receipt, "use-a", current, 262144,
    )
    is Err(@publication_host.TransferNotCommitted),
  )
  let before = @site.site_status(site)
  authorized.val = false
  assert_true(
    @publication_host.validate_client_retained_input_transfer_current(
      producer, request, current,
    )
    is Err(@publication_host.AuthorizationUnavailable),
  )
  let after = @site.site_status(site)
  assert_eq(before[6], after[6])
  assert_eq(before[7], after[7])
  authorized.val = true
  let expired = @publication_host.install_client_retained_input_current(
    () => site,
    () => standard_transfer_input_cid("c"),
    () => 4102444800001L,
    (_, _) => true,
  )
  assert_true(
    @publication_host.validate_client_retained_input_transfer_current(
      producer, request, expired,
    )
    is Err(@publication_host.TransferExpired),
  )
}

///|
test "retained task binding restores exact original ports without changing Transfer revision" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  let value = prepare_native_remote_retained_task_input(
    producer,
    transfer,
    receipt,
    "use-a",
    retained_transfer_current(site, standard_transfer_input_cid("c")),
    262144,
  ).unwrap()
  let saved = native_remote_retained_task_input_binding(value)
  let revision = @transfer.record_revision(transfer)
  let recovered_site = @site.create_site(
    "site-a",
    1,
    standard_transfer_input_cid("a"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  for _ in 0..<2 {
    let restored = admit_native_remote_retained_task_input(
      saved,
      producer,
      transfer,
      receipt,
      "use-a",
      retained_transfer_current(
        recovered_site,
        standard_transfer_input_cid("c"),
      ),
      262144,
    ).unwrap()
    assert_eq(
      @remote.remote_input_binding_cid(restored.binding),
      @remote.remote_input_binding_cid(saved),
    )
    assert_eq(@transfer.record_revision(transfer), revision)
  }
  assert_true(
    admit_native_remote_retained_task_input(
      saved,
      producer,
      transfer,
      receipt,
      "use-b",
      retained_transfer_current(
        recovered_site,
        standard_transfer_input_cid("c"),
      ),
      262144,
    )
    is Err(InvalidBinding),
  )
  let foreign = @remote.prepare_remote_input_binding(
    @remote.remote_input_binding_body(saved).replace(
      old="\"consumer_input_port\":\"input\"",
      new="\"consumer_input_port\":\"other\"",
    ),
    262144,
  ).unwrap()
  assert_true(
    admit_native_remote_retained_task_input(
      foreign,
      producer,
      transfer,
      receipt,
      "use-a",
      retained_transfer_current(
        recovered_site,
        standard_transfer_input_cid("c"),
      ),
      262144,
    )
    is Err(InvalidBinding),
  )
}

///|
test "retained task binding refuses uncommitted Transfer and current authority or generation mismatch" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(false)
  assert_true(
    prepare_native_remote_retained_task_input(
      producer,
      transfer,
      receipt,
      "use-a",
      retained_transfer_current(site, standard_transfer_input_cid("c")),
      262144,
    )
    is Err(TransferNotCommitted),
  )
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  assert_true(
    prepare_native_remote_retained_task_input(
      producer,
      transfer,
      receipt,
      "use-a",
      retained_transfer_current(site, "authority-b"),
      262144,
    )
    is Err(ForeignAuthority),
  )
  let restarted = @site.create_site(
    "site-a",
    2,
    standard_transfer_input_cid("a"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  assert_true(
    prepare_native_remote_retained_task_input(
      producer,
      transfer,
      receipt,
      "use-a",
      retained_transfer_current(restarted, standard_transfer_input_cid("c")),
      262144,
    )
    is Err(StaleSiteGeneration),
  )
  assert_true(@transfer.record_is_destination_committed(transfer))
  assert_true(
    @publication_host.client_retained_input_producer_available(producer),
  )
}

///|
test "retained task restoration rechecks current authorization and lifetime" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  let mut allowed = true
  let mut now = 1791158400000L
  let current = install_native_remote_retained_input_current(
    () => site,
    () => standard_transfer_input_cid("c"),
    () => now,
    (_, _) => allowed,
  )
  let value = prepare_native_remote_retained_task_input(
    producer, transfer, receipt, "use-a", current, 262144,
  ).unwrap()
  let saved = native_remote_retained_task_input_binding(value)
  allowed = false
  assert_true(
    admit_native_remote_retained_task_input(
      saved, producer, transfer, receipt, "use-a", current, 262144,
    )
    is Err(AuthorizationUnavailable),
  )
  allowed = true
  now = 4102444800000L
  assert_true(
    admit_native_remote_retained_task_input(
      saved, producer, transfer, receipt, "use-a", current, 262144,
    )
    is Err(TransferExpired),
  )
  // Neither refusal claims that computation is unknown or cleanup has completed.
  assert_true(
    @publication_host.client_retained_input_producer_available(producer),
  )
  assert_true(@transfer.record_is_destination_committed(transfer))
}

///|
test "retained task input cannot borrow a foreign receipt or alias its source holding" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  ignore(receipt)
  let foreign = @transfer.prepare_destination_receipt(
    standard_transfer_input_request(),
    "foreign-destination",
  ).unwrap()
  let source_reuse = @transfer.prepare_destination_receipt(
    @transfer.record_request(transfer),
    "producer-material",
  ).unwrap()
  for candidate in [foreign, source_reuse] {
    assert_true(
      prepare_native_remote_retained_task_input(
        producer,
        transfer,
        candidate,
        "use-a",
        retained_transfer_current(site, standard_transfer_input_cid("c")),
        262144,
      )
      is Err(ForeignTransfer),
    )
  }
  assert_true(
    @publication_host.client_retained_input_producer_available(producer),
  )
  assert_true(@transfer.record_is_destination_committed(transfer))
}

///|
test "retained task input rechecks revocation after issuing the canonical body" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  let mut checks = 0
  let current = install_native_remote_retained_input_current(
    () => site,
    () => standard_transfer_input_cid("c"),
    () => 1791158400000L,
    (_, _) => {
      checks += 1
      checks == 1
    },
  )
  assert_true(
    prepare_native_remote_retained_task_input(
      producer, transfer, receipt, "use-a", current, 262144,
    )
    is Err(AuthorizationUnavailable),
  )
  assert_eq(checks, 2)
  assert_true(
    @publication_host.client_retained_input_producer_available(producer),
  )
  assert_eq(@transfer.record_revision(transfer), 3)
}

///|
test "retained binding admits reconstructed owner records in the current generation" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  let saved = native_remote_retained_task_input_binding(
    prepare_native_remote_retained_task_input(
      producer,
      transfer,
      receipt,
      "use-a",
      retained_transfer_current(site, standard_transfer_input_cid("c")),
      262144,
    ).unwrap(),
  )
  let current_site = @site.create_site(
    "site-a",
    1,
    standard_transfer_input_cid("a"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    current_site, "actql-remote-site/0.1",
  ).unwrap()
  let dispatch = @publication_host.client_retained_input_producer_dispatch(
    producer,
  )
  let restored_record = @remote.commit_dispatch_acceptance(
      @remote.prepare_dispatch_acceptance(journal, dispatch).unwrap(),
      true,
    ).unwrap().1
  let subject = @publication_host.client_retained_input_producer_subject(
    producer,
  )
  let evidence = @publication_host.client_retained_input_producer_evidence(
    producer,
  )
  let (material, holding, _, _) = @remote.remote_managed_output_subject_retention(
    subject,
  )
  @remote.restore_dispatch_record(
    restored_record,
    5,
    3,
    2,
    0,
    true,
    false,
    material,
    holding,
    @remote.remote_execution_evidence_cid(evidence),
  ).unwrap()
  // Reconstruct preparation and admitted Run instead of reusing the prior edge.
  let restored_producer = @publication_host.prepare_client_retained_input_producer(
    retained_transfer_edge(),
    restored_record,
    evidence,
    subject,
  ).unwrap()
  let restored_transfer = @transfer.restore_record(
    @transfer.record_request(transfer),
    @transfer.record_projection(transfer),
  ).unwrap()
  let restored = admit_native_remote_retained_task_input(
    saved,
    restored_producer,
    restored_transfer,
    receipt,
    "use-a",
    retained_transfer_current(current_site, standard_transfer_input_cid("c")),
    262144,
  ).unwrap()
  assert_eq(
    @remote.remote_input_binding_cid(restored.binding),
    @remote.remote_input_binding_cid(saved),
  )
  assert_eq(
    @transfer.record_revision(restored_transfer),
    @transfer.record_revision(transfer),
  )
  assert_eq(
    @remote.dispatch_request_attempt_identity(
      @publication_host.client_retained_input_producer_dispatch(
        restored_producer,
      ),
    ),
    @remote.dispatch_request_attempt_identity(dispatch),
  )
  // This tests common owner reconstruction, not durable Native reader/holding
  // restoration or a public Coordinator restart with running child processes.
}

///|
test "portable retained issuer and Native adapter preserve exact binding bytes" {
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  let current = retained_transfer_current(
    site,
    standard_transfer_input_cid("c"),
  )
  let common = @publication_host.prepare_client_retained_task_input(
    producer,
    transfer,
    receipt,
    "use-a",
    current.common,
    262144,
  ).unwrap()
  let native = prepare_native_remote_retained_task_input(
    producer, transfer, receipt, "use-a", current, 262144,
  ).unwrap()
  assert_eq(
    @remote.remote_input_binding_body(native.binding),
    @remote.remote_input_binding_body(
      @publication_host.client_retained_task_input_binding(common),
    ),
  )
  assert_eq(
    @remote.remote_input_binding_cid(native.binding),
    @remote.remote_input_binding_cid(
      @publication_host.client_retained_task_input_binding(common),
    ),
  )
  let physical = @publication_host.client_retained_task_input_physical(common)
  let admitted = @publication_host.admit_client_transfer_input(
    @publication_host.client_transfer_binding(physical),
    262144,
    8,
    65536,
    1048576L,
  ).unwrap()
  assert_eq(
    @remote.remote_input_binding_body(native.physical.binding),
    @remote.remote_input_binding_body(
      @publication_host.client_transfer_binding(admitted),
    ),
  )
}

///|
test "owned retained input issues only its exact checked consumer dispatch" {
  let (prepared, compilation, allowed, definition) = retained_transfer_run()
  let (producer, transfer, receipt, site) = retained_transfer_fixture(true)
  let current = retained_transfer_current(
    site,
    standard_transfer_input_cid("c"),
  )
  let input = @publication_host.prepare_client_retained_task_input(
    producer,
    transfer,
    receipt,
    "use-a",
    current.common,
    262144,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    standard_transfer_input_cid("c"),
    "retained-caller",
  ).unwrap()
  let selected : @publication_host.ClientValuesSiteSelection = {
    site_key: "site-a",
    site_generation: 1,
    runtime_bundle_cid: standard_transfer_input_cid("a"),
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
    obligations_cid: standard_transfer_input_cid("2"),
    budget_cid: standard_transfer_input_cid("3"),
    evidence_issuer_capability_cid: standard_transfer_input_cid("4"),
    grant_cid: standard_transfer_input_cid("5"),
  }
  let issue = fn(
    task : Int,
    selected : @publication_host.ClientValuesSiteSelection,
    current : @publication_host.ClientRetainedInputCurrent,
  ) {
    @publication_host.prepare_client_retained_task_dispatch(
      prepared,
      compilation,
      @publication_host.client_compiled_run_admission(allowed),
      definition,
      request,
      task,
      1,
      "consumer-dispatch",
      selected,
      input,
      current,
    )
  }
  let dispatch = issue(1, selected, current.common).unwrap()
  let ports = @publication_host.client_retained_input_edge_projection(
    @publication_host.client_retained_input_producer_edge(producer),
  )
  assert_eq(@remote.dispatch_request_task_scope(dispatch), (ports[0], ports[5]))
  assert_true(
    @remote.remote_input_binding_matches_dispatch(
      @publication_host.client_retained_task_input_binding(input),
      dispatch,
    ),
  )
  assert_true(
    issue(0, selected, current.common)
    is Err(@publication_host.Edge(@publication_host.MissingEdge)),
  )
  let foreign : @publication_host.ClientValuesSiteSelection = {
    ..selected,
    site_generation: 2,
  }
  assert_true(
    issue(1, foreign, current.common) is Err(@publication_host.ForeignConsumer),
  )
  let denied = @publication_host.install_client_retained_input_current(
    () => site,
    () => standard_transfer_input_cid("c"),
    () => 1791158400000L,
    (_, _) => false,
  )
  assert_true(
    issue(1, selected, denied)
    is Err(@publication_host.Input(@publication_host.AuthorizationUnavailable)),
  )
  // The ordinary issuer continues to refuse dependent tasks without owned custody.
  assert_true(
    @publication_host.prepare_client_task_dispatch(
      prepared,
      compilation,
      @publication_host.client_compiled_run_admission(allowed),
      definition,
      request,
      1,
      1,
      "consumer-dispatch",
      selected,
    )
    is Err(@publication_host.UnsupportedTask),
  )
}

///|
test "retained Transfer refuses producer release during current authorization" {
  let release : Ref[(() -> Unit)?] = Ref(None)
  let (producer, transfer, _, site) = retained_transfer_fixture(
    false,
    release=Some(release),
  )
  let request = @transfer.record_request(transfer)
  let before = @site.site_status(site)
  let current = @publication_host.install_client_retained_input_current(
    () => site,
    () => standard_transfer_input_cid("c"),
    () => 1791158400000L,
    (_, _) => {
      release.val.unwrap()()
      true
    },
  )
  assert_true(
    @publication_host.validate_client_retained_input_transfer_current(
      producer, request, current,
    )
    is Err(@publication_host.ProducerUnavailable),
  )
  assert_false(
    @publication_host.client_retained_input_producer_available(producer),
  )
  assert_eq(@site.site_status(site)[6], before[6])
}
