///|
// Independent three-seed, two-consumer checked programs. These exercise the
// actual configured capacity Plan, not a caller-supplied budget or Carrier value.
let closed_graph_demand_program : String =
  #|{"version":"actql/0.1","id":"closed-graph","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"id":3,"src":3,"dst":3},{"id":1,"src":1,"dst":1},{"id":2,"src":2,"dst":2}]},"as":"seed"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"}]}}]}],"edges":[{"name":"E","from":"seed","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"Link","properties":{"mode":"no_properties"}}]}]},"as":"carrier"},{"from":"carrier","match_nodes":{"definition":"N","where":"true","fields":["id"]},"as":"rows"},{"from":"rows","filter":"id >= 1","as":"kept"},{"from":"kept","sort":[{"id":"desc"}],"as":"ordered"},{"from":"ordered","select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}},{"id":"consumer_a","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}},{"id":"consumer_b","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}},"consumed_a":{"from":{"stage":"consumer_a","result":"out"}},"consumed_b":{"from":{"stage":"consumer_b","result":"out"}}}}

///|
let closed_events_demand_program : String =
  #|{"version":"actql/0.1","id":"closed-events","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3},{"id":1},{"id":2}]},"as":"seed"},{"from":"seed","to_events":{"id":"id","time":"id"},"as":"carrier"},{"from":"carrier","watermark_events":{"watermark_ms":2,"policy":"mark"},"as":"computed"},{"from":"computed","events":true,"as":"rows"},{"from":"rows","filter":"id >= 1","as":"kept"},{"from":"kept","sort":[{"id":"desc"}],"as":"ordered"},{"from":"ordered","select":["id","late"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","late"]}}},{"id":"consumer_a","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","late"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","late"]}}},{"id":"consumer_b","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","late"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","late"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}},"consumed_a":{"from":{"stage":"consumer_a","result":"out"}},"consumed_b":{"from":{"stage":"consumer_b","result":"out"}}}}

///|
let closed_vectors_demand_program : String =
  #|{"version":"actql/0.1","id":"closed-vectors","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false}},"rows":[{"id":3,"embedding":[0,2]},{"id":1,"embedding":[0,2]},{"id":2,"embedding":[0,2]}]},"as":"seed"},{"from":"seed","to_vectors":{"id":"id","vector":"embedding"},"as":"carrier"},{"from":"carrier","normalize_vectors":true,"as":"computed"},{"from":"computed","vectors":true,"as":"rows"},{"from":"rows","filter":"id >= 1","as":"kept"},{"from":"kept","sort":[{"id":"desc"}],"as":"ordered"},{"from":"ordered","select":["id","embedding"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","embedding"]}}},{"id":"consumer_a","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","embedding"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","embedding"]}}},{"id":"consumer_b","inputs":{"r":{"result":{"stage":"source","result":"out"}}},"steps":[{"from":"r","select":["id","embedding"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","embedding"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}},"consumed_a":{"from":{"stage":"consumer_a","result":"out"}},"consumed_b":{"from":{"stage":"consumer_b","result":"out"}}}}

///|
// Same explicit Graph-construction Host policy used by the original retained
// family fixture. These are checker inputs, never a replacement Resource budget.
let closed_carrier_demand_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":4096,"max_replacements":4096,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
test "closed Carrier facts configure every original task without replacing provider storage" {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    closed_carrier_demand_environment,
    "sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261",
    { text_time: true, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    graph=true,
  ).unwrap()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for
    (family, text, tasks, bound) in [
      ("graph", closed_graph_demand_program, 8, 6),
      ("events", closed_events_demand_program, 9, 3),
      ("vectors", closed_vectors_demand_program, 9, 3),
    ] {
    let prepared = @publication_host.prepare_effect_free_client_program(
      text,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    let graph = @publication_host.prepared_client_graph(prepared)
    let sequences = prepare_client_local_sequences(
      prepared,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    assert_eq(@strategy.graph_task_count(graph), tasks)
    let plan = client_local_capacity_plan(
      sequences,
      100,
      scalar_values=true,
      graph=Some(graph),
    )
    let demand = plan.demand_inventory.unwrap()
    assert_true(demand.carrier_values)
    assert_eq(demand.closed_rows, Some(bound))
    assert_eq(plan.admitted_rows, 100)
    assert_eq(plan.execution.rows.max_rows, bound)
    assert_true(plan.values.max_nodes < 20000)
    assert_true(plan.imports.wire.max_nodes < 100000)
    assert_true(plan.exports.wire.max_nodes < 100000)
    assert_true(client_local_capacity_plan_matches(plan, sequences, 100))
    // Both independent consumers and all split Carrier task occurrences stay.
    assert_eq(plan.sequences.length(), tasks)
    let work = Ref(client_local_schema_proof_work())
    assert_eq(
      client_local_closed_carrier_bound(sequences, graph, work),
      Some(bound),
    )
    assert_true(
      client_local_closed_carrier_bound(sequences, graph, Ref(0)) is None,
    )
    let foreign = @publication_host.prepare_effect_free_client_program(
      text,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    assert_true(
      client_local_closed_carrier_bound(
        sequences,
        @publication_host.prepared_client_graph(foreign),
        Ref(client_local_schema_proof_work()),
      )
      is None,
    )
    let original = source_free_installed_managed_preparation_owned(
      Pure(prepared),
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
    ).unwrap()
    assert_eq(original.sequences.length(), tasks)
    assert_true(original.limits.retained_bytes <= 536870912L)
    assert_true(original.limits.execution_bytes <= 536870912L)
    println(
      "CLOSED_CARRIER \{family} tasks=\{tasks} bound=\{bound} retained=\{original.limits.retained_bytes} execution=\{original.limits.execution_bytes}",
    )
  }
}
