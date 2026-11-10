///|
// Independently sealed Node-crypto input fixture. These are admission inputs,
// not expected compiler output; the original unknown-policy fixture is unchanged.
fn request_policy_supplement_wire_environment() -> @environment.WireEnvironment {
  @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:8ce7f3bc8625daef2903b26709bb3e48decb3be40c075e9752ae21a4ae65ff2d","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"extra":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":3,"max_response_bytes_per_page":4096,"max_rows_per_key":2,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"tenant":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"internal","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","correlation":{"cardinality":"zero_or_many","identity":["id"],"request_fields":["id"],"response_fields":["id"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:cb9d1071a1fe7e799d97da75baeba7045a8e4953e744bde1982fba3e395281c2","output":{"carrier":"relation","data_policy":{"cid":"sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"tenant":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":3,"max_response_bytes_per_page":4096,"max_rows_per_key":2,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"extra":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"internal","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:41cd4c21c23e88757c3141ff44c9cb8e696a1eeb381a4163a77f45fa032f7d61","host_policy_profile":{"capacity":{"max_aggregate_array_items":1,"max_artifact_bytes":1,"max_artifact_rows":1,"max_effect_items":1,"max_graph_input_edges":1,"max_graph_input_nodes":1,"max_graph_output_rows":1,"max_graph_paths":1,"max_infer_items":1,"max_model_input_tokens_per_item":1,"max_model_request_bytes_per_item":1,"max_model_total_duration_ms":1,"max_nested_value_bytes":1,"max_nested_value_depth":1,"max_relation_output_rows":1,"max_temporal_matches_per_key":1,"max_temporal_output_rows":1,"version":"actql-capacity-host-policy/0.1"},"lookup_execution":{"max_network_attempts_per_request":3,"max_request_bytes_per_attempt":1024,"max_total_decoded_response_bytes":65536,"max_total_duration_ms":30000,"max_total_request_bytes":1,"max_total_response_bytes":1,"version":"actql-lookup-execution-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","correlation":{"cardinality":"zero_or_many","identity":["id"],"request_fields":["id"],"response_fields":["id"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:cb9d1071a1fe7e799d97da75baeba7045a8e4953e744bde1982fba3e395281c2","output":{"carrier":"relation","data_policy":{"cid":"sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:41cd4c21c23e88757c3141ff44c9cb8e696a1eeb381a4163a77f45fa032f7d61",
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    },
  ).unwrap()
}

///|
fn request_policy_supplement_environment() -> @checked.CheckEnvironment {
  @checked.checking_environment(
    request_policy_supplement_wire_environment(),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
let policy_supplement_program : String =
  #|{"version":"actql/0.1","id":"policy-parent","params":{"key":{"type":"number","default":1}},"stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"id":{"$param":"key"},"tenant":null}}},"steps":[{"from":"remote","filter":"id > 0"},{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}

///|
fn request_policy_supplement_fixture(
  environment : @checked.CheckEnvironment,
  supplied? : Bool = false,
  effect? : Bool = false,
  document? : String? = None,
  current? : () -> Bool = () => true,
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) {
  let text = if effect {
    policy_supplement_program.replace(
      old="\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}",
      new="\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\"]}},\"effects\":{\"save\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"out\"},\"id\":\"id\",\"set\":{\"Name\":{\"field\":\"id\"}}}}}}",
    )
  } else {
    policy_supplement_program
  }
  let text = document.unwrap_or(text)
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input, current~),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(
    parent,
    input,
    text.length().to_int64() + 32L,
    text.length().to_int64() + 32L,
  ).unwrap()
  let limits = @publication_host.client_standard_program_preparation_limits()
  let source = prepare_request_native_program_input(
    parent,
    input,
    request_native_test_value(text),
    native_json_reader,
    limits.checking.input,
    supplied=if supplied {
      Some(request_native_test_value("{\"key\":1}"))
    } else {
      None
    },
  ).unwrap()
  construct_program_json_preparation(source).unwrap() |> ignore
  reconcile_program_json_preparation_structure(source).unwrap() |> ignore
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  prepare_request_original_computation_check(
    parent,
    input,
    environment,
    publication,
    [],
    limits,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  (parent, input)
}

///|
fn request_policy_checked_program(
  parent : ClientRequestPreparation[Array[Int]],
) -> @checked.CheckedProgram raise {
  let child = parent.program_check.unwrap()
  if child.effect_candidate is Some(candidate) {
    return @checked.effect_computation_checked_program(candidate)
  }
  guard parent.program_check.unwrap().check_outcome
    is Some(@checked.Checked(program)) else {
    fail("original Source Program must retain a checked outcome")
  }
  program
}

///|
fn request_policy_checked_egress(
  parent : ClientRequestPreparation[Array[Int]],
) -> @checked.SourceExecution raise {
  let program = request_policy_checked_program(parent)
  for index in 0..<@checked.source_execution_count(program) {
    let original = @checked.source_execution_at(program, index).unwrap()
    if @checked.source_execution_kind(original) is @checked.RequestEgress {
      return original
    }
  }
  fail("original Source request egress required")
}

///|
fn request_policy_supplement_evidence(
  parent : ClientRequestPreparation[Array[Int]],
) -> @checked.HostRequestValuePolicyEvidence raise {
  // Explicit trusted verification port for this Core component only. It
  // establishes no ordinary Host verification, Source permission or I/O.
  @checked.bind_host_verified_request_value_policy_cid(
    request_policy_checked_egress(parent),
    "sha256:bc75d87043cc6314215460b4e0f2fbf5a72363edbe989ee7bb69acfc9021c808",
    1000000,
    1000000,
    100000,
    100,
  )
}
