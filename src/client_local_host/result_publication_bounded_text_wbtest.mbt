///|
fn bounded_text_result_prepared() -> @publication_host.PreparedClientProgram {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  // Independently authored counterpart of the normal SQL literal/projection:
  // one Boolean witness, one 64000-byte literal and 263 copied aliases.
  let names = Array::makei(263, index => "f" + index.to_string())
  let selected = names.map(name => "{\"" + name + "\":\"t\"}").join(",")
  let fields = names.map(name => "\"" + name + "\"").join(",")
  let document = "{\"version\":\"actql/0.1\",\"id\":\"bounded-result-text\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"unit\":true}]},\"as\":\"seed\"},{\"derive\":{\"t\":{\"literal\":\"" +
    "x".repeat(64000) +
    "\"}}},{\"select\":[" +
    selected +
    "],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[" +
    fields +
    "]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"s\",\"result\":\"rows\"}}}}"
  let standard = @publication_host.client_standard_program_preparation_limits()
  // Only this ASCII fixture selects its exact input envelope. Production and
  // shared test defaults, node/depth limits and work policy stay unchanged.
  let limits = {
    ..standard,
    checking: {
      ..standard.checking,
      input: {
        ..standard.checking.input,
        source: {
          ..standard.checking.input.source,
          max_input_bytes: document.length(),
        },
        tree: {
          ..standard.checking.input.tree,
          max_total_string_bytes: document.length(),
        },
      },
    },
  }
  @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits,
  ).unwrap()
}

///|
test "bounded Text Result wire counts every alias independently of larger work policy" {
  let prepared = bounded_text_result_prepared()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_result_count(graph), 1)
  let occurrence = @strategy.graph_result_occurrence(graph, 0).unwrap()
  let schema = @results.port_schema(
    @execution.managed_result_occurrence_port(occurrence),
  )
  assert_eq(@schema.field_count(schema), 263)
  for index in 0..<263 {
    let field = @schema.field_at(schema, index).unwrap()
    match @schema.field_contract(field).shape {
      @contract.Text(bounds) => assert_eq(bounds.max_utf8_bytes, Some(64000L))
      _ => fail("Original projected literal Text contract is required")
    }
  }
  // 263 * 64000 payload bytes, 942 original name bytes, and the existing
  // sixfold escaping/punctuation formula; no output row is sampled or emitted.
  let expected = 101005312
  assert_eq(client_local_result_scalar_wire_bytes(graph, 1), Some(expected))
  // This test prices static publication metadata, not a default Host run.
  // Obtain the SAME checked sequences/row domain before choosing each work
  // policy below; an unrelated default runtime need not admit this wide row.
  let assets = @publication_host.client_local_product_assets()
  let selected = @publication_host.client_standard_program_preparation_limits()
  let standard_codec = @publication_host.client_standard_pure_compilation_limits()
  let sequences = prepare_client_local_sequences_owned(
    Pure(prepared),
    prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap(),
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    compilation_limits=Some({
      ..standard_codec,
      max_wire_bytes: selected.checking.compilation.artifacts.bytes,
      max_nodes: selected.checking.compilation.artifacts.nodes,
      max_depth: selected.checking.compilation.artifacts.depth,
    }),
  ).unwrap()
  let admitted_rows = @publication_host.prepared_client_values_max_rows(
    prepared,
  )
  for work in [30000000, 100000000] {
    let plan = client_local_capacity_plan(
      sequences,
      admitted_rows,
      scalar_values=true,
      graph=Some(graph),
      source_free_max_work=Some(work),
    )
    let limits = client_node_publication_limits(prepared, 536870912, plan).unwrap()
    assert_eq(limits.max_rows, 1)
    assert_eq(limits.values.max_work, work)
    assert_eq(limits.values.max_text_bytes, work)
    assert_eq(limits.payload_wire.max_bytes, expected)
    assert_eq(limits.logical_wire.max_bytes, expected)
    // The exact other coheld obligations observed in normal875 were1050997B.
    // They remain additional durable objects; they are never discarded here.
    assert_true(expected + 1050997 < 536870912)
    let narrow = client_node_publication_limits(prepared, 8388608, plan).unwrap()
    assert_eq(narrow.payload_wire.max_bytes, 8388608)
    assert_eq(narrow.values.max_work, work)
  }
  let small_work = client_local_capacity_plan(
    sequences,
    admitted_rows,
    scalar_values=true,
    graph=Some(graph),
    source_free_max_work=Some(1),
  )
  let limits = client_node_publication_limits(prepared, 536870912, small_work).unwrap()
  // A publication optimization cannot enlarge the selected execution counter
  // or its narrower output ceiling. Actual work/row refusal keeps its owner.
  assert_eq(limits.values.max_work, 1)
  assert_eq(limits.values.max_text_bytes, 1)
  assert_true(limits.payload_wire.max_bytes < 16834521)
}

///|
test "bounded Text Result wire preserves unknown and overflow refusal" {
  let unbounded = @publication_host.prepared_client_graph(
    result_envelope_fixture(),
  )
  assert_true(client_local_result_scalar_wire_bytes(unbounded, 1) is None)
  let bounded = @publication_host.prepared_client_graph(
    bounded_text_result_prepared(),
  )
  assert_true(client_local_result_scalar_wire_bytes(bounded, -1) is None)
  assert_true(
    client_local_result_scalar_wire_bytes(bounded, 2147483647) is None,
  )
}
