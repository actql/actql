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

///|
// An open acquired Source keeps its original row/text/Carrier limits. The
// Compute suffix borrows checked Event record schemas, not a closed-item count.
let captured_events_schema_budget_program : String =
  #|{"id":"captured-events-schema-budget","results":{"windowed":{"from":{"stage":"events","result":"r"}},"consumed":{"from":{"stage":"consumer","result":"r"}}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]},{"id":"events","inputs":{"rows":{"result":{"stage":"acquire","result":"r"}}},"steps":[{"from":"rows","derive":{"clock_ms":{"field":"id"},"label":{"literal":"event"}},"as":"clocked"},{"from":"clocked","to_events":{"id":"id","time":"clock_ms"},"as":"source"},{"from":"source","window_events":{"kind":"fixed","size":2},"as":"windowed"},{"from":"windowed","events":true,"as":"bridged"},{"from":"bridged","select":["id","label","window_start_ms","window_end_ms"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","label","window_start_ms","window_end_ms"]}}},{"id":"consumer","inputs":{"x":{"result":{"stage":"events","result":"r"}}},"steps":[{"select":["id","window_start_ms"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","window_start_ms"]}}}],"version":"actql/0.1"}

///|
test "captured Event suffix uses original record schemas without a closed Source cardinality" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    captured_events_schema_budget_program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = prepare_client_local_sequences(
    prepared,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  let tail = sequences[1:].to_owned()
  let plan = client_local_capacity_plan(
    tail,
    100,
    scalar_values=true,
    graph=Some(graph),
    graph_offset=1,
  )
  let demand = plan.value_node_demand.unwrap()
  assert_true(plan.demand_inventory.unwrap().carrier_values)
  assert_eq(plan.demand_inventory.unwrap().closed_rows, None)
  assert_eq(plan.admitted_rows, 100)
  assert_eq(plan.execution.rows.max_rows, 100)
  assert_eq(plan.values.max_text_bytes, 500000)
  assert_true(demand.nodes < client_local_general_value_nodes())
  assert_eq(plan.measurement.max_nodes, 2 * demand.nodes)
  assert_eq(plan.measurement.max_bytes, 500000)
  assert_eq(plan.measurement.max_depth, 100)
  assert_true(client_local_capacity_plan_matches(plan, tail, 100))
  // The actual configured per-task reservations still coexist. No max-only
  // fold, retired input discount, sampled row count or smaller policy is used.
  let requirement = original_row_requirement(prepared)
  let acquisition = original_row_acquisition_fixture(requirement)
  let capacity = installed_row_capture_capacity(acquisition).unwrap()
  let request = @publication_host.prepare_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "captured-event-budget",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let capture = prepare_installed_managed_capture_plan(
    prepared,
    request,
    [capacity],
    [4096L],
    [2048L],
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  assert_true(capture.limits.execution_bytes <= 536870912L)
  assert_true(capture.limits.retained_bytes <= 536870912L)
  assert_eq(capture.captures.length(), 1)
  assert_eq(@strategy.graph_result_count(graph), 2)
}

///|
test "Event record proof borrows only complete original fields and leaves closed-carrier selection unchanged" {
  let id = @schema.Unqualified("id")
  let clock = @schema.Unqualified("time")
  let fields = [
    (id, Some(@contract.primitive(StringType, nullable=false))),
    (clock, Some(@contract.primitive(TimestampType, nullable=false))),
  ]
  let complete = @carrier.rows(
    fields,
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let original = @carrier.complete_schema(complete).unwrap()
  let events = @carrier.events(complete, id~, time=clock).unwrap()
  assert_true(
    physical_equal(
      client_local_record_value_schema(events, true).unwrap(),
      original,
    ),
  )
  assert_true(client_local_record_value_schema(events, false) is None)
  let open = @carrier.rows(
    fields,
    field_set=Open,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    client_local_record_value_schema(
      @carrier.events(open, id~, time=clock).unwrap(),
      true,
    )
    is None,
  )
  let unknown = @carrier.rows(
    [fields[0], fields[1], (@schema.Unqualified("payload"), None)],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    client_local_record_value_schema(
      @carrier.events(unknown, id~, time=clock).unwrap(),
      true,
    )
    is None,
  )
  assert_true(
    physical_equal(
      client_local_record_value_schema(@carrier.relation(complete), false).unwrap(),
      original,
    ),
  )
}

///|
test "Signed64 record cells retain one value node without a numeric wire proof" {
  let signed = @contract.primitive(Signed64Type, nullable=false)
  assert_eq(client_local_json_contract_nodes(signed, Ref(1), 1), Some(1L))
  let schema = @schema.from_fields(
    [(@schema.Unqualified("id"), signed)],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  assert_true(client_local_scalar_schema_width(schema) is None)
  assert_eq(client_local_json_schema_nodes(schema, 1, 1), Some((2L, 0)))
}

///|
let captured_multi_events_schema_budget_program : String =
  #|{"id":"captured-two-source-events-schema-budget","results":{"windowed":{"from":{"stage":"events","result":"r"}},"consumed":{"from":{"stage":"consumer","result":"r"}}},"stages":[{"id":"left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]},{"id":"right","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]},{"id":"join","inputs":{"l":{"result":{"stage":"left","result":"r"}},"r":{"result":{"stage":"right","result":"r"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":100,"select":{"id":"left.id","right_id":"right.id"}},"as":"joined"},{"from":"joined","sort":[{"id":"asc"}],"as":"out"}],"results":{"r":{"from":"out","fields":["id","right_id"]}}},{"id":"events","inputs":{"rows":{"result":{"stage":"join","result":"r"}}},"steps":[{"from":"rows","derive":{"clock_ms":{"cast":{"value":{"substring":{"value":{"literal":"event 1"},"start":{"literal":7}}},"target":{"type":"number"}}},"label":{"literal":"event"},"other_label":{"literal":"second"}},"as":"clocked"},{"from":"clocked","to_events":{"id":"id","time":"clock_ms"},"as":"source"},{"from":"source","window_events":{"kind":"fixed","size":2},"as":"windowed"},{"from":"windowed","events":true,"as":"bridged"},{"from":"bridged","filter":"id > 0","as":"kept"},{"from":"kept","select":["id","label","other_label","window_start_ms","window_end_ms"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","label","other_label","window_start_ms","window_end_ms"]}}},{"id":"consumer","inputs":{"x":{"result":{"stage":"events","result":"r"}}},"steps":[{"select":["id","window_start_ms"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","window_start_ms"]}}}],"version":"actql/0.1"}

///|
test "two captured Sources retain every Event task under the original execution policy" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    captured_multi_events_schema_budget_program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let capacities = []
  for index in 0..<2 {
    let requirement = prepare_local_query_requirement(
      prepared,
      index,
      0,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    capacities.push(
      installed_row_capture_capacity(
        original_row_acquisition_fixture(requirement),
      ).unwrap(),
    )
  }
  let request = @publication_host.prepare_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "captured-multi-event-budget",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let capture = prepare_installed_managed_capture_plan(
    prepared,
    request,
    capacities,
    [4096L, 4096L],
    [2048L, 2048L],
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let plan = capture.capacity_plan
  println(
    "MULTI_EVENT tasks=\{@strategy.graph_task_count(capture.graph)} nodes=\{plan.values.max_nodes} retained=\{capture.limits.retained_bytes} execution=\{capture.limits.execution_bytes} proof=\{plan.value_node_demand is Some(_)}",
  )
  let mut all_tasks = 0L
  let mut largest_task = 0L
  for task in 2..<@strategy.graph_task_count(capture.graph) {
    let envelope = @local_driver.local_dispatch_preparation_task_capacity(
      capture.configuration.dispatch,
      task,
    ).unwrap()
    all_tasks += envelope.execution_bytes
    largest_task = Int64::max(largest_task, envelope.execution_bytes)
  }
  // Every original reservation survives with its downstream borrowers.
  // A maximum-only fold would pass the ceiling but lose those obligations.
  assert_eq(@strategy.graph_task_count(capture.graph), 10)
  assert_eq(@strategy.graph_result_count(capture.graph), 2)
  // Two Direct occurrences also retain owner/inventory/Some/coordinates
  // (5H/6R/8W) and both original/check arrays (4H/26R/4W). The same
  // retained selector overlaps every task; its graph and queries are borrowed.
  let selector = @execution.preparation_representation_cost({
    record_headers: 9L,
    reference_slots: 32L,
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(capture.limits.execution_bytes, all_tasks + selector)
  assert_true(all_tasks > largest_task)
  assert_eq(
    plan.measurement.max_nodes,
    2 * plan.value_node_demand.unwrap().nodes,
  )
  assert_eq(plan.measurement.max_bytes, 500000)
  assert_eq(plan.values.max_text_bytes, 500000)
  assert_eq(plan.execution.rows.max_rows, 100)
  // Nine original data edges: seven row transfers and two Carrier views.
  // Carrier views never construct the row wire importer at runtime.
  assert_eq(
    @local_driver.local_dispatch_preparation_transfer_bytes(
      capture.configuration.dispatch,
    ),
    Some(7000000L),
  )
  assert_eq(capture.captures.length(), 2)
  assert_true(capture.limits.execution_bytes <= 536870912L)
  assert_true(capture.limits.retained_bytes <= 536870912L)
}
