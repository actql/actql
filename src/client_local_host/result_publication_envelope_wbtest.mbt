///|
fn result_envelope_fixture() -> @publication_host.PreparedClientProgram raise {
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
test "result envelope accepts exact row boundaries and falls back outside them" {
  let graph = @publication_host.prepared_client_graph(result_envelope_fixture())
  for (rows, workspace) in [(1, 8), (20000, 40006)] {
    let envelope = client_local_result_envelope(graph, rows).unwrap()
    assert_eq(envelope.fields, 2)
    assert_eq(envelope.mapping_work, 16)
    assert_eq(envelope.order_terms, 6)
    assert_eq(envelope.workspace_entries, workspace)
  }
  for rows in [-1, 0, 20001] {
    assert_true(client_local_result_envelope(graph, rows) is None)
  }
}

///|
test "result publication limits reuse the checked graph envelope and payload cap" {
  let prepared = result_envelope_fixture()
  let graph = @publication_host.prepared_client_graph(prepared)
  let rows = @publication_host.prepared_client_values_max_rows(prepared)
  let envelope = client_local_result_envelope(graph, rows).unwrap()
  let limits = client_node_values_publication_limits(prepared, 4096).unwrap()
  assert_eq(limits.max_rows, 10000)
  assert_eq(limits.values.max_depth, 64)
  assert_eq(limits.values.max_work, 1000000)
  assert_eq(limits.values.max_nodes, 1000000)
  assert_eq(limits.values.max_text_bytes, 10000000)
  assert_eq(limits.max_result_order_work, 10000)
  assert_eq(limits.payload_wire.max_nodes, 1000000)
  assert_eq(limits.payload_wire.max_depth, 64)
  assert_eq(limits.payload_wire.max_columns, 100)
  assert_eq(limits.payload_wire.max_order_work, 1000000)
  assert_eq(limits.logical_wire.max_nodes, 1000003)
  assert_eq(limits.logical_wire.max_depth, 66)
  assert_eq(limits.schema.max_fields, 100)
  assert_eq(limits.schema.max_bytes, 100000)
  assert_eq(limits.schema.max_nodes, 10000)
  assert_eq(limits.schema.max_depth, 64)
  assert_eq(limits.max_batch_bytes, 65536)
  assert_eq(limits.max_result_mapping_work, envelope.mapping_work)
  assert_eq(limits.max_result_fields, envelope.fields)
  assert_eq(
    limits.max_result_workspace_entries,
    envelope.publication_workspace_entries,
  )
  assert_eq(limits.payload_wire.max_bytes, 4096)
  assert_eq(limits.logical_wire.max_bytes, 4096)
  assert_true(limits.schema.max_fields >= limits.max_result_fields)
  assert_true(client_node_values_publication_limits(prepared, 0) is None)
}
