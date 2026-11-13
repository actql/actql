///|
// The original upstream Result is a subset. The later Model Result already
// owns the complete checked policy; no new union policy or authority is made.
test "mixed Result policies select the existing complete policy independent of root order" {
  for
    roots in [
      "{\"a_original\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}},\"z_reviewed\":{\"from\":{\"stage\":\"confirm\",\"result\":\"rows\"}}}",
      "{\"a_reviewed\":{\"from\":{\"stage\":\"confirm\",\"result\":\"rows\"}},\"z_original\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}",
    ] {
    let prepared = mixed_whole_infer_test_program(roots=Some(roots))
    let program = @strategy.graph_program(prepared.graph)
    let original = @checked.publication_source_policy(
      @checked.unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    let complete = @checked.publication_source_policy(
      @checked.unit_publication_at(program, 2, 0).unwrap(),
    ).unwrap()
    assert_false(
      client_publication_policy_covers_source_responses(program, original),
    )
    assert_true(
      client_publication_policy_covers_source_responses(program, complete),
    )
    assert_eq(
      prepared_client_publication_data_policy_cid(prepared),
      Some(complete.cid),
    )
    let bodies = prepared_client_publication_policy_bodies(
      prepared, 100000, 10000, 100,
    ).unwrap()
    assert_eq(bodies[0].1, complete.cid)
  }
}

///|
test "mixed Result policies without an existing complete representative stay refused" {
  let prepared = mixed_whole_infer_test_program(
    roots=Some(
      "{\"original\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}",
    ),
  )
  assert_eq(prepared_client_publication_data_policy_cid(prepared), None)
}

///|
test "mixed Result policies preserve unknown and reject equal CID foreign contributors" {
  let (original, limited) = publication_policy_join_pair(
    multi_source_prepared(publication_policy_join_program),
  )
  let (foreign_original, foreign_limited) = publication_policy_join_pair(
    multi_source_prepared(publication_policy_join_program),
  )
  assert_true(client_publication_policy_contains_result(limited, original))
  assert_false(client_publication_policy_contains_result(original, limited))
  assert_eq(original.cid, foreign_original.cid)
  assert_eq(limited.cid, foreign_limited.cid)
  assert_false(
    client_publication_policy_contains_result(limited, foreign_original),
  )
  assert_false(
    client_publication_policy_contains_result(limited, foreign_limited),
  )
  let prepared = multi_source_prepared(publication_policy_join_program)
  let program = @strategy.graph_program(prepared.graph)
  let partial = @checked.publication_source_policy(
    @checked.unit_publication_at(program, 0, 0).unwrap(),
  ).unwrap()
  let (complete, conservative) = publication_policy_join_pair(prepared)
  assert_true(client_publication_policy_contains_result(conservative, partial))
  assert_true(client_publication_policy_contains_result(complete, partial))
  assert_false(client_publication_policy_contains_result(partial, conservative))
}

///|
// Independently hashed existing Catalog/environment contracts: the original
// left Source is Public and the right Source is Internal. No runtime grant.
let mixed_known_policy_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:5a3782dba4137bf5158817086038cba563b147ffbeac02fd8097422a7f8462be","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:5a3782dba4137bf5158817086038cba563b147ffbeac02fd8097422a7f8462be"},{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:dadbf9cb08280610faba740ca1699ba0f21e3f4f53c466bf1e47cc077aca7451","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:dadbf9cb08280610faba740ca1699ba0f21e3f4f53c466bf1e47cc077aca7451"}],"connector_catalogs":[{"catalog_cid":"sha256:370a20e504ba8d42463f6adf972fa3df9ae4e70657ba28e70f2da0e72f416f0d","commands":[],"connector_id":"crm/right","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"internal","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:49c2c1c7fa4075fd3b6fe3f4475af5fc8928c0f4afb6555407777475e436fa71","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:dadbf9cb08280610faba740ca1699ba0f21e3f4f53c466bf1e47cc077aca7451","output":{"carrier":"relation","data_policy":{"cid":"sha256:49c2c1c7fa4075fd3b6fe3f4475af5fc8928c0f4afb6555407777475e436fa71","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:d1c58c8d46139d70addf0b1017a8a63ccfe8a842a994f2a441e11d00c69b4455","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"public","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:a1e83b879115b755b01507c5b68d8e7ff53a0d0a5b8c226cd14d165e92d5d903","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:5a3782dba4137bf5158817086038cba563b147ffbeac02fd8097422a7f8462be","output":{"carrier":"relation","data_policy":{"cid":"sha256:a1e83b879115b755b01507c5b68d8e7ff53a0d0a5b8c226cd14d165e92d5d903","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"internal","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:49c2c1c7fa4075fd3b6fe3f4475af5fc8928c0f4afb6555407777475e436fa71","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"public","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:a1e83b879115b755b01507c5b68d8e7ff53a0d0a5b8c226cd14d165e92d5d903","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:a789489e096d742e32125c57801a7b8662174befe3c3b2a6369e19533a471115","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":4096,"max_replacements":4096,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"internal","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:dadbf9cb08280610faba740ca1699ba0f21e3f4f53c466bf1e47cc077aca7451","source_data_policy_cid":"sha256:49c2c1c7fa4075fd3b6fe3f4475af5fc8928c0f4afb6555407777475e436fa71","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:dadbf9cb08280610faba740ca1699ba0f21e3f4f53c466bf1e47cc077aca7451"},{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"public","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:5a3782dba4137bf5158817086038cba563b147ffbeac02fd8097422a7f8462be","source_data_policy_cid":"sha256:a1e83b879115b755b01507c5b68d8e7ff53a0d0a5b8c226cd14d165e92d5d903","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:5a3782dba4137bf5158817086038cba563b147ffbeac02fd8097422a7f8462be"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:dadbf9cb08280610faba740ca1699ba0f21e3f4f53c466bf1e47cc077aca7451","output":{"carrier":"relation","data_policy":{"cid":"sha256:49c2c1c7fa4075fd3b6fe3f4475af5fc8928c0f4afb6555407777475e436fa71","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:5a3782dba4137bf5158817086038cba563b147ffbeac02fd8097422a7f8462be","output":{"carrier":"relation","data_policy":{"cid":"sha256:a1e83b879115b755b01507c5b68d8e7ff53a0d0a5b8c226cd14d165e92d5d903","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
test "mixed Result policies retain the real Internal full policy above a Public subset" {
  let source = publication_policy_join_program.replace(
    old="\"results\":{\"original\":{\"from\":{\"stage\":\"join_sources\",\"result\":\"original\"}},\"answer\":{\"from\":{\"stage\":\"join_sources\",\"result\":\"limited\"}}}",
    new="\"results\":{\"a_subset\":{\"from\":{\"stage\":\"acquire_left\",\"result\":\"rows\"}},\"z_complete\":{\"from\":{\"stage\":\"join_sources\",\"result\":\"original\"}}}",
  )
  assert_true(source != publication_policy_join_program)
  let environment = admit_client_check_environment(
    mixed_known_policy_environment,
    "sha256:a789489e096d742e32125c57801a7b8662174befe3c3b2a6369e19533a471115",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = match
    prepare_effect_free_client_program(
      source,
      Json,
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Check(issue)) => raise @checked.diagnostic_cause(issue)
    Err(_) => fail("known classification fixture preparation")
  }
  let program = @strategy.graph_program(prepared.graph)
  let subset = @checked.publication_source_policy(
    @checked.unit_publication_at(program, 0, 0).unwrap(),
  ).unwrap()
  let (complete, unknown) = publication_policy_join_pair(prepared)
  assert_eq(
    @checked.publication_policy_classification(subset),
    @environment.Public,
  )
  assert_eq(
    @checked.publication_policy_classification(complete),
    @environment.Internal,
  )
  assert_eq(
    @checked.publication_policy_classification(unknown),
    @environment.Unknown,
  )
  assert_eq(
    complete.cid,
    "sha256:65f0cd9597dce786765a8cb776def2da1ef9a1c2644c3dae3c0f4a15cbc1e24f",
  )
  assert_true(client_publication_policy_contains_result(complete, subset))
  assert_false(client_publication_policy_contains_result(subset, complete))
  assert_false(client_publication_policy_contains_result(complete, unknown))
  assert_true(client_publication_policy_contains_result(unknown, complete))
  assert_eq(
    prepared_client_publication_data_policy_cid(prepared),
    Some(complete.cid),
  )
}
