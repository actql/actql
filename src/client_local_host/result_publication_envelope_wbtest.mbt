///|
fn publication_plan_fixture(
  prepared : @publication_host.PreparedClientProgram,
) -> ClientInstalledManagedSourceFreePreparation {
  let assets = @publication_host.client_local_product_assets()
  prepare_installed_managed_source_free_with_contracts(
    prepared,
    prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap(),
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
}

///|
fn result_envelope_fixture() -> @publication_host.PreparedClientProgram {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  // Empty rows deliberately rule out inferring schema or order from sampled output.
  let document =
    #|{"version":"actql/0.1","id":"result-envelope","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"string","nullable":false}},"rows":[]},"as":"v"}],"results":{"wide":{"from":"v","fields":["x","y"],"order_by":[{"x":"asc"},{"x":"asc"}]},"narrow":{"from":"v","fields":["x"],"order_by":[{"x":"asc"},{"x":"asc"}]}}}],"results":{"first":{"from":{"stage":"s","result":"wide"}},"alias":{"from":{"stage":"s","result":"wide"}},"small":{"from":{"stage":"s","result":"narrow"}}}}
  @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "result envelope counts aliases and repeated order occurrences without output rows" {
  let prepared = result_envelope_fixture()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_result_count(graph), 3)
  let envelope = client_local_result_envelope(graph, 17).unwrap()
  assert_eq(envelope.fields, 2)
  assert_eq(envelope.mapping_work, 16)
  assert_eq(envelope.order_terms, 6)
  assert_eq(envelope.workspace_entries, 40)
}

///|
test "result envelope derives row workspace and rejects representation overflow" {
  let graph = @publication_host.prepared_client_graph(result_envelope_fixture())
  for (rows, workspace) in [(1, 8), (20000, 40006), (100000, 200006)] {
    let envelope = client_local_result_envelope(graph, rows).unwrap()
    assert_eq(envelope.fields, 2)
    assert_eq(envelope.mapping_work, 16)
    assert_eq(envelope.order_terms, 6)
    assert_eq(envelope.workspace_entries, workspace)
  }
  assert_eq(
    client_local_result_envelope(graph, 2147483647).unwrap().workspace_entries,
    2147483647,
  )
  for rows in [-1, 0] {
    assert_true(client_local_result_envelope(graph, rows) is None)
  }
}

///|
test "result publication limits reuse the checked graph envelope and payload cap" {
  let prepared = result_envelope_fixture()
  let graph = @publication_host.prepared_client_graph(prepared)
  // Empty original Values has the checked one-row floor, not the identity profile.
  let rows = 1
  let envelope = client_local_result_envelope(graph, rows).unwrap()
  let original = publication_plan_fixture(prepared)
  let exported = original.capacity_plan.exports
  let limits = prepared_installed_managed_publication_limits(
    original, prepared, 4096,
  ).unwrap()
  assert_eq(limits.max_rows, 1)
  assert_eq(limits.values.max_depth, 64)
  assert_eq(limits.values.max_work, exported.values.max_work)
  assert_eq(limits.values.max_nodes, exported.values.max_nodes)
  assert_eq(limits.values.max_text_bytes, exported.values.max_text_bytes)
  assert_eq(limits.max_result_order_work, 10000)
  assert_eq(limits.payload_wire.max_nodes, exported.wire.max_nodes)
  assert_eq(
    limits.payload_wire.max_depth,
    Int::min(exported.wire.max_depth, 64),
  )
  assert_eq(limits.payload_wire.max_columns, envelope.fields)
  assert_eq(limits.payload_wire.max_order_work, exported.wire.max_order_work)
  assert_eq(limits.logical_wire.max_nodes, exported.wire.max_nodes + 3)
  assert_eq(
    limits.logical_wire.max_depth,
    Int::min(exported.wire.max_depth, 64) + 2,
  )
  assert_eq(limits.schema.max_fields, envelope.fields)
  assert_eq(limits.schema.max_bytes, 79)
  assert_eq(limits.schema.max_nodes, 10000)
  assert_eq(limits.schema.max_depth, 64)
  assert_eq(limits.max_batch_bytes, exported.max_batch_bytes)
  assert_eq(limits.max_result_mapping_work, envelope.mapping_work)
  assert_eq(limits.max_result_fields, envelope.fields)
  assert_eq(
    limits.max_result_workspace_entries,
    envelope.publication_workspace_entries,
  )
  assert_eq(limits.payload_wire.max_bytes, 4096)
  assert_eq(limits.logical_wire.max_bytes, 4096)
  assert_true(limits.schema.max_fields >= limits.max_result_fields)
  assert_true(
    prepared_installed_managed_publication_limits(
      publication_plan_fixture(prepared),
      prepared,
      0,
    )
    is None,
  )
}

///|
test "checked Result schema bound uses exact projected contracts and fails closed on work exhaustion" {
  let graph = @publication_host.prepared_client_graph(result_envelope_fixture())
  let limits : @execution.RelationSchemaIdentityLimits = {
    max_fields: 2,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 64,
  }
  // x Number + y String; exact canonical field map is 79 UTF-8 bytes.
  assert_eq(client_local_result_schema_bytes(graph, limits), Some(79))
  assert_eq(
    client_local_result_schema_bytes(graph, { ..limits, max_bytes: 79, }),
    Some(79),
  )
  assert_eq(
    client_local_result_schema_bytes(graph, { ..limits, max_bytes: 78, }),
    None,
  )
  assert_eq(client_local_result_schema_bytes(graph, limits, max_work=3), None)
  for index in 0..<@strategy.graph_result_count(graph) {
    let occurrence = @strategy.graph_result_occurrence(graph, index).unwrap()
    let schema = @results.port_schema(
      @execution.managed_result_occurrence_port(occurrence),
    )
    let actual = @execution.identify_relation_schema(schema, limits).unwrap()
    let (bytes, _, _) = @execution.relation_schema_usage(actual)
    assert_true(bytes <= 79)
    assert_eq(
      @utf8.encode(@execution.relation_schema_wire(actual)).length(),
      bytes,
    )
  }
}

///|
test "publication bridge metadata is projected only from the exact sealed Run" {
  let assets = @publication_host.client_local_product_assets()
  let prepared = result_envelope_fixture()
  let first = open_source_free_local_retained_host(
    prepared,
    prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap(),
    assets.values,
    0L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
  ).unwrap()
  let second = open_source_free_local_retained_host(
    prepared,
    prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap(),
    assets.values,
    0L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
  ).unwrap()
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(first),
  ).unwrap()
  let original = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(first),
  )
  let foreign = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(second),
  )
  let limits = @local_driver.local_publication_bridge_limits(
    installed, original,
  ).unwrap()
  assert_true(limits.entries >= 2)
  assert_true(limits.name_bytes >= 2)
  assert_true(
    @local_driver.local_publication_bridge_limits(installed, foreign) is None,
  )
}

///|
test "publication projection borrows the original plan before admission and rejects same-shaped foreign Program" {
  let prepared = result_envelope_fixture()
  let foreign = result_envelope_fixture()
  let assets = @publication_host.client_local_product_assets()
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap(),
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let projected = prepared_installed_managed_publication_limits(
    original, prepared, 4096,
  ).unwrap()
  assert_eq(projected.schema.max_bytes, 79)
  assert_eq(projected.max_rows, original.capacity_plan.execution.rows.max_rows)
  assert_true(
    prepared_installed_managed_publication_limits(original, foreign, 4096)
    is None,
  )
  // The prepared identity profile is not rewritten by an allocation projection.
  assert_eq(
    @publication_host.prepared_client_values_max_rows(prepared),
    original.capacity_plan.admitted_rows,
  )
  assert_eq(
    prepared_installed_managed_publication_limits(
      publication_plan_fixture(prepared),
      prepared,
      4096,
    ).unwrap().schema.max_bytes,
    79,
  )
}

///|
test "unordered Result publication row work follows original 10001 and 100000 row authority" {
  for rows in [10001, 100000] {
    let prepared = sequence_demand_fixture(rows, false)
    let assets = @publication_host.client_local_product_assets()
    let original = prepare_installed_managed_source_free_with_contracts(
      prepared,
      prepare_installed_sequence_contracts(
        assets.registry,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ).unwrap(),
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      retained_output=true,
      provider_factory=_ => [],
    ).unwrap()
    let projected = prepared_installed_managed_publication_limits(
      original, prepared, 10000000,
    ).unwrap()
    assert_eq(projected.max_result_order_work, rows)
    assert_true(projected.max_result_workspace_entries >= 2 * rows)
  }
}

///|
test "Node publication consumes the same export demand beyond old fixed limits" {
  let prepared = result_envelope_fixture()
  let original = publication_plan_fixture(prepared).capacity_plan
  // Inert checked-Plan projection inputs isolate the old boundary. They do not
  // create a Resource owner, Run, allocation or accepted installed publication.
  for bytes in [9999999, 10000000, 10000001] {
    let exported = {
      ..original.exports,
      values: {
        ..original.exports.values,
        max_nodes: 1000001,
        max_text_bytes: bytes,
      },
      wire: { ..original.exports.wire, max_bytes: bytes, max_nodes: 1000001, },
    }
    let plan = { ..original, exports: exported, }
    let projected = client_node_publication_limits_original(bytes, plan).unwrap()
    assert_eq(projected.values.max_nodes, 1000001)
    assert_eq(projected.values.max_text_bytes, bytes)
    assert_eq(projected.payload_wire.max_bytes, bytes)
    assert_eq(projected.payload_wire.max_nodes, 1000001)
    assert_eq(projected.logical_wire.max_nodes, 1000004)
    // An explicitly narrower Store-object policy still wins. Neither row nor
    // value budgets are reissued, and no total-store quantity is added here.
    let narrow = client_node_publication_limits_original(4096, plan).unwrap()
    assert_eq(narrow.payload_wire.max_bytes, 4096)
    assert_eq(narrow.values.max_text_bytes, bytes)
  }
  assert_true(client_node_publication_limits_original(0, original) is None)
  for (nodes, depth) in [(2147483645, 64), (100, 2147483646)] {
    let overflow = {
      ..original,
      exports: {
        ..original.exports,
        wire: { ..original.exports.wire, max_nodes: nodes, max_depth: depth, },
      },
    }
    assert_true(client_node_publication_limits_original(4096, overflow) is None)
  }
}

///|
test "Node publication keeps an already tighter original codec depth and finite batch" {
  let original = publication_plan_fixture(result_envelope_fixture()).capacity_plan
  let plan = {
    ..original,
    exports: {
      ..original.exports,
      values: { ..original.exports.values, max_depth: 7, },
      wire: { ..original.exports.wire, max_depth: 8, },
      max_batch_bytes: 1024,
    },
  }
  let limits = client_node_publication_limits_original(4096, plan).unwrap()
  assert_eq(limits.values.max_depth, 7)
  assert_eq(limits.payload_wire.max_depth, 8)
  assert_eq(limits.logical_wire.max_depth, 10)
  assert_eq(limits.max_batch_bytes, 1024)
}
