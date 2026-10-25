///|
/// Pure compiler diagnostic. This does not reserve the ordinary Host Ledger;
/// a successful artifact is NOT a claim that its constructor quote fits512MiB.
test "derived compilation envelope emits original numeric100k beyond former node cap" {
  let rows : Array[String] = []
  for i in 0..<100000 {
    rows.push("{\"v0\":" + i.to_string() + "}")
  }
  let source = "{\"version\":\"actql/0.1\",\"id\":\"numeric-scale\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{\"v0\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows.join(",") +
    "]}}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[\"v0\"]}}}],\"results\":{\"answer0\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let facts = closed_values_lexical_facts(source, source.length()).unwrap()
  assert_eq(facts.input_bytes, 1289175)
  let assets = @publication_host.client_local_product_assets()
  // Same installed Local selector as installed-host-policy.mjs, not a new
  // fixture-only row grant: derive both ceilings from the original policy.
  let selected_rows = client_local_materialized_row_ceiling(
      client_local_resource_policy(),
    )
    .unwrap()
    .to_string()
  assert_eq(selected_rows, "2097152")
  let environment_wire = assets.environment
    .replace(
      old="\"max_relation_output_rows\":1000",
      new="\"max_relation_output_rows\":" + selected_rows,
    )
    .replace(
      old="\"max_artifact_rows\":1000",
      new="\"max_artifact_rows\":" + selected_rows,
    )
    .replace(
      old="sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
      new="sha256:4bc4705ac02241481ea468ccfa0842cd5ef16fdc0103463ed3caedfac872031a",
    )
  assert_true(environment_wire != assets.environment)
  let environment = @publication_host.admit_client_check_environment(
    environment_wire,
    "sha256:4bc4705ac02241481ea468ccfa0842cd5ef16fdc0103463ed3caedfac872031a",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let standard = @publication_host.client_standard_program_preparation_limits()
  let prepared = @publication_host.prepare_effect_free_client_program(
    source,
    Json,
    environment,
    None,
    {
      ..standard,
      checking: {
        ..standard.checking,
        input: {
          source: {
            max_input_bytes: facts.input_bytes,
            max_nodes: facts.node_upper,
            max_depth: facts.depth_upper,
          },
          tree: {
            max_nodes: facts.node_upper,
            max_depth: facts.depth_upper,
            max_string_bytes: facts.longest_quoted_utf16,
            max_total_string_bytes: facts.quoted_utf16_units,
          },
          max_stages: 1,
        },
      },
    },
  ).unwrap()
  let layout = closed_values_compilation_layout(facts, 1, 100000).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let sequence = @publication_host.prepared_client_values_sequence_limits(
    prepared,
  )
  assert_true(
    @publication_host.emit_prepared_client_values_pipeline(
      prepared,
      0,
      sequence,
      layout.max_wire_bytes,
      100000,
      layout.max_depth,
    )
    is Err(@publication_host.Encoding),
  )
  let compiled = @publication_host.issue_prepared_client_values_compilation(
    prepared,
    manifests,
    sequence,
    layout.max_facts,
    layout.max_witnesses,
    layout.max_wire_bytes,
    layout.max_nodes,
    layout.max_depth,
  ).unwrap()
  let plan = @publication_host.client_values_compilation_plan(compiled)
  let wire = @publication_host.client_values_executable_plan_wire(plan)
  assert_true(wire.length() > 1000000)
  assert_true(wire.contains("99999"))
  assert_eq(
    @publication_host.client_values_compilation_result_names(compiled),
    ["answer0"],
  )
  println(
    "PURE_COMPILER_100K wire=" +
    wire.length().to_string() +
    " cid=" +
    @publication_host.client_values_executable_plan_cid(plan) +
    " B=" +
    layout.max_wire_bytes.to_string() +
    " N=" +
    layout.max_nodes.to_string() +
    " D=" +
    layout.max_depth.to_string(),
  )
}
