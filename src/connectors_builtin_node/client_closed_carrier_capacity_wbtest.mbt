///|
// Independent three-seed, two-consumer checked programs. These exercise the
// actual configured capacity Plan, not a caller-supplied budget or Carrier value.
let node_closed_graph_demand_program : String =
  #|{"version":"actql/0.1","id":"closed-graph","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"id":3,"src":3,"dst":3},{"id":1,"src":1,"dst":1},{"id":2,"src":2,"dst":2}]},"as":"seed"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"}]}}]}],"edges":[{"name":"E","from":"seed","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"Link","properties":{"mode":"no_properties"}}]}]},"as":"carrier"},{"from":"carrier","match_nodes":{"definition":"N","where":"true","fields":["id"]},"as":"rows"},{"from":"rows","filter":"id >= 1","as":"kept"},{"from":"kept","sort":[{"id":"desc"}],"as":"ordered"},{"from":"ordered","select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}},{"id":"consumer_a","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}},{"id":"consumer_b","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}},"consumed_a":{"from":{"stage":"consumer_a","result":"out"}},"consumed_b":{"from":{"stage":"consumer_b","result":"out"}}}}

///|
let node_closed_events_demand_program : String =
  #|{"version":"actql/0.1","id":"closed-events","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3},{"id":1},{"id":2}]},"as":"seed"},{"from":"seed","to_events":{"id":"id","time":"id"},"as":"carrier"},{"from":"carrier","watermark_events":{"watermark_ms":2,"policy":"mark"},"as":"computed"},{"from":"computed","events":true,"as":"rows"},{"from":"rows","filter":"id >= 1","as":"kept"},{"from":"kept","sort":[{"id":"desc"}],"as":"ordered"},{"from":"ordered","select":["id","late"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","late"]}}},{"id":"consumer_a","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","late"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","late"]}}},{"id":"consumer_b","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","late"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","late"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}},"consumed_a":{"from":{"stage":"consumer_a","result":"out"}},"consumed_b":{"from":{"stage":"consumer_b","result":"out"}}}}

///|
let node_closed_vectors_demand_program : String =
  #|{"version":"actql/0.1","id":"closed-vectors","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false}},"rows":[{"id":3,"embedding":[0,2]},{"id":1,"embedding":[0,2]},{"id":2,"embedding":[0,2]}]},"as":"seed"},{"from":"seed","to_vectors":{"id":"id","vector":"embedding"},"as":"carrier"},{"from":"carrier","normalize_vectors":true,"as":"computed"},{"from":"computed","vectors":true,"as":"rows"},{"from":"rows","filter":"id >= 1","as":"kept"},{"from":"kept","sort":[{"id":"desc"}],"as":"ordered"},{"from":"ordered","select":["id","embedding"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","embedding"]}}},{"id":"consumer_a","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","embedding"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","embedding"]}}},{"id":"consumer_b","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","embedding"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","embedding"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}},"consumed_a":{"from":{"stage":"consumer_a","result":"out"}},"consumed_b":{"from":{"stage":"consumer_b","result":"out"}}}}

///|
// Same explicit Graph-construction Host policy used by the original retained
// family fixture. These are checker inputs, never a replacement Resource budget.
let node_closed_carrier_demand_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":4096,"max_replacements":4096,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
// Real installed Node provider factory and final configured task fold. No
// transport, Account, native Run or physical backing is supplied by this test.
test "closed Carrier Node factory retains actual simultaneous envelopes within original Resource policy" {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    node_closed_carrier_demand_environment,
    "sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261",
    { text_time: true, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    graph=true,
  ).unwrap()
  let contracts = client_prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for
    (family, document, tasks) in [
      ("graph", node_closed_graph_demand_program, 8),
      ("events", node_closed_events_demand_program, 9),
      ("vectors", node_closed_vectors_demand_program, 9),
    ] {
    let prepared = @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    assert_eq(client_program_task_count(prepared), tasks)
    let configured = client_program_prepare_installed_managed_source_free_with_contracts(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      true,
    ).unwrap()
    let limits = @client_local_host.prepared_installed_managed_source_free_requirements(
      configured,
    )
    assert_true(limits[3] <= 536870912L)
    assert_true(limits[4] <= 536870912L)
    println(
      "CONFIGURED_CARRIER \{family} tasks=\{tasks} retained=\{limits[3]} execution=\{limits[4]}",
    )
  }
}
