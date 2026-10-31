///|
// Existing package authoring inputs only; not restored state or physical evidence.
let precheckpoint_original_program : String =
  #|{"version":"actql/0.1","id":"local-update-source","stages":[{"id":"source","inputs":{"table":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"filter":{"gte":[{"field":"id"},{"literal":0}]}},{"select":["id",{"value":"id"}],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}}},{"id":"apply","inputs":{"input":{"result":{"stage":"source","result":"out"}}},"steps":[{"select":["id","value"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"},"id":"id","set":{"Name":{"field":"value"}}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}

///|
let precheckpoint_original_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89","sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8"],"read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"},{"capability_contract_cids":["sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89","sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"connector_catalogs":[{"catalog_cid":"sha256:b256d9e2361b791cc2df19e1f87f9d53feb0616c539f07dd62e8bc566259e162","commands":[],"connector_id":"crm/right","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm/main","connector_id":"crm/main","connector_version":"fixture"},{"connector":"crm/right","connector_id":"crm/right","connector_version":"fixture"},{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:8d4ce402b0b54632daceba146a82fb96125483f78abb5d99c7e716f055a18d26","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:275614ef615205a8e8eef3cdd1f15f5ef28b25fa90332600fc816def40eb2c58","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"number"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:c000fb12383456a0e123e74501d164b96bb886251dbb44f301661070321be8e0","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"},{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","source_data_policy_cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
fn effect_projection_fixture() -> ClientRemoteEffectTaskProgress {
  let (_, _, effect_limits) = client_composed_effect_base_fixture()
  let environment = admit_client_check_environment(
    precheckpoint_original_environment,
    "sha256:8d4ce402b0b54632daceba146a82fb96125483f78abb5d99c7e716f055a18d26",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = prepare_client_effect_computation(
    precheckpoint_original_program,
    Json,
    environment,
    None,
    [],
    effect_limits,
  ).unwrap()
  let limits = run_materials_limits()
  let original = issue_prepared_client_effect_local_update_normalization(
    prepared,
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
    normalization=Some(original),
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "scope", "source-request-run", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  inspect_client_remote_effect_task_progress(
    allowed,
    definition,
    "sha256:" + "c".repeat(64),
    [],
  ).unwrap()
}

///|
fn effect_projection_claims(
  progress : ClientRemoteEffectTaskProgress,
) -> Array[ClientRemoteEffectTaskRunClaim] {
  progress.progress.keys.map(task_key => {
    task_key,
    dispatch_cid: None,
    dispatch_reserved: false,
    physical_start_claimed: false,
  })
}

///|
fn effect_projection_state(
  value : ClientRemoteEffectTaskRunProjection,
) -> Map[String, Json] {
  let parsed = @json.parse(
    client_remote_effect_task_run_projection_fields(value)[0],
  ) catch {
    _ => abort("Expected valid unpublished candidate")
  }
  guard parsed is Object(fields) else { abort("Expected original Run fields") }
  fields
}

///|
test "Effect pre-checkpoint original task inventory is preparing without invented publication" {
  let progress = effect_projection_fixture()
  let projected = project_client_remote_effect_task_run(
    progress,
    "2026-10-09T00:01:00.000Z",
    false,
    effect_projection_claims(progress),
  ).unwrap()
  let state = effect_projection_state(projected)
  assert_eq(state.get("status"), Some(Json::string("preparing")))
  assert_eq(state.get("result_available"), Some(Json::boolean(false)))
  assert_eq(state.get("revision"), None)
  let fields = client_remote_effect_task_run_projection_fields(projected)
  assert_eq(fields[3], "0")
  assert_eq(fields[4], "0")
}

///|
test "Effect pre-checkpoint cancellation request alone is not a whole Run pre-start fence" {
  let progress = effect_projection_fixture()
  let projected = project_client_remote_effect_task_run(
    progress,
    "2026-10-09T00:01:00.000Z",
    true,
    effect_projection_claims(progress),
  ).unwrap()
  assert_eq(
    effect_projection_state(projected).get("status"),
    Some(Json::string("preparing")),
  )
}

///|
test "Effect pre-checkpoint missing original claimed observation remains reconciliation" {
  let progress = effect_projection_fixture()
  let claims = effect_projection_claims(progress)
  claims[0] = {
    ..claims[0],
    dispatch_cid: Some("sha256:" + "d".repeat(64)),
    dispatch_reserved: true,
    physical_start_claimed: true,
  }
  let projected = project_client_remote_effect_task_run(
    progress, "2026-10-09T00:01:00.000Z", true, claims,
  ).unwrap()
  let state = effect_projection_state(projected)
  assert_eq(state.get("status"), Some(Json::string("needs_reconciliation")))
  guard state.get("next_action") is Some(Object(action)) else {
    abort("Expected original action")
  }
  assert_eq(action.get("kind"), Some(Json::string("reconcile_run")))
}

///|
test "Effect pre-checkpoint completed computation and task cleanup cannot complete cancellation" {
  let original = effect_projection_fixture()
  let requested = prepare_client_effect_request_identity(
    client_effect_compilation_owner(original.allowed.compilation),
    original.progress.authority,
    "precheckpoint-original",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let source_request = bound_effect_source_dispatch(
    original.allowed,
    original.progress.definition,
    requested,
  )
  // White-box reducer counter only. These authored task facts are not
  // physical Site evidence, a whole Run stop or a cleanup acknowledgement.
  let progress = {
    ..original,
    progress: {
      ..original.progress,
      requests: original.progress.keys.map(_ => Some(source_request)),
      completed: original.progress.keys.map(_ => true),
      execution_complete: true,
      cleanup_complete: true,
      observations: original.progress.keys.map(_ => {
        Some({
          execution: Some(@remote.NativeSettled),
          cleanup: Some(@remote.CleanupReleased),
          evidence_rejected: false,
          revision: 1,
          execution_terminal: true,
          cleanup_complete: true,
        })
      }),
    },
  }
  let claims = effect_projection_claims(progress).map(claim => {
    ..claim,
    dispatch_cid: Some(@remote.dispatch_request_identity(source_request)),
    dispatch_reserved: true,
    physical_start_claimed: true,
  })
  let projected = project_client_remote_effect_task_run(
    progress, "2026-10-09T00:01:00.000Z", true, claims,
  ).unwrap()
  let state = effect_projection_state(projected)
  assert_eq(state.get("status"), Some(Json::string("running")))
  assert_eq(state.get("result_available"), Some(Json::boolean(false)))
  let fields = client_remote_effect_task_run_projection_fields(projected)
  assert_eq(fields[3], "0")
  assert_eq(fields[4], "0")
}

///|
test "Effect pre-checkpoint original claim set refuses missing duplicate foreign and inconsistent rows" {
  let progress = effect_projection_fixture()
  let now = "2026-10-09T00:01:00.000Z"
  let claims = effect_projection_claims(progress)
  assert_true(
    project_client_remote_effect_task_run(progress, now, false, [])
    is Err(InvalidStartClaims),
  )
  let duplicate = claims.copy()
  duplicate[1] = duplicate[0]
  assert_true(
    project_client_remote_effect_task_run(progress, now, false, duplicate)
    is Err(InvalidStartClaims),
  )
  let foreign = claims.copy()
  foreign[0] = { ..foreign[0], task_key: "foreign-task", }
  assert_true(
    project_client_remote_effect_task_run(progress, now, false, foreign)
    is Err(InvalidStartClaims),
  )
  let invalid = claims.copy()
  invalid[0] = { ..invalid[0], physical_start_claimed: true, }
  assert_true(
    project_client_remote_effect_task_run(progress, now, false, invalid)
    is Err(InvalidStartClaims),
  )
}
