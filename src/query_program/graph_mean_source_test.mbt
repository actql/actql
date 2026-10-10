///|
test "Mean DATA generator retains its ordered occurrences in an independent Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"mean_graphs":{"with":["aql_data_2","aql_data_2","aql_data_2"],"weights":[1,2,0],"support":{"nodes":1,"edges":1},"properties":{"nodes":{"p":{"mean":{"missing":"exclude","nulls":"exclude"}}},"edges":{}}},"as":"aql_data_3"},{"from":"aql_data_3","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_data_set(
    graph_union_prefix() +
    "DATA combined = mean_graphs(with: [g, g, g], weights: [1, 2, 0], support: {nodes: 1, edges: 1}, properties: {nodes: {p: {mean: {missing: 'exclude', nulls: 'exclude'}}}, edges: {}}); FROM combined |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(actual), semantic(expected))
  check_graph_union_source(expected)
  check_graph_union_source(actual)
}

///|
test "Mean source leaves weight support and property admission to the common checker" {
  for
    options in [
      "with: [g, g], weights: [0, 0], support: {nodes: 1, edges: 1}, properties: {nodes: {p: 'exact_equal'}, edges: {}}",
      "with: [g, g], weights: [1], support: {nodes: 1, edges: 1}, properties: {nodes: {p: 'exact_equal'}, edges: {}}",
      "with: [g, g], weights: [1, -1], support: {nodes: 1, edges: 1}, properties: {nodes: {p: 'exact_equal'}, edges: {}}",
      "with: [g, g], weights: [1, 1], support: {nodes: 2, edges: 1}, properties: {nodes: {p: 'exact_equal'}, edges: {}}",
      "with: [g, g], weights: [1, 1], support: {nodes: 1, edges: 1}, properties: {nodes: {missing: 'exact_equal'}, edges: {}}",
    ] {
    let program = compile_data_set(
      graph_union_prefix() +
      "DATA combined = mean_graphs(" +
      options +
      "); FROM combined |> node_rows() |> SELECT p",
    )
    assert_true(
      @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      )
      is Rejected(_),
      msg=options,
    )
  }
}

///|
test "Mean source keeps differently produced samples in explicit port order" {
  let program = compile_data_set(
    graph_union_prefix() +
    "DATA doubled = FROM g |> union_graphs(with: [g], merge: {node_properties: {p: 'number_sum'}, edge_properties: {}}); " +
    "DATA combined = mean_graphs(with: [doubled, g, doubled], weights: [1, 2, 0], support: {nodes: 1, edges: 1}, properties: {nodes: {p: {mean: {missing: 'exclude', nulls: 'exclude'}}}, edges: {}}); " +
    "FROM combined |> node_rows() |> SELECT p, node_key",
  )
  check_graph_union_source(program)
  let stage = @program.stages(program)[0]
  let body = @wire.open_object(@program.stage_body(stage)).unwrap()
  let steps = @wire.elements(@wire.required(body, "steps").unwrap()).unwrap()
  let mean_step = @wire.open_object(steps[steps.length() - 3]).unwrap()
  let options = @wire.open_object(
    @wire.required(mean_step, "mean_graphs").unwrap(),
  ).unwrap()
  let samples = @wire.elements(@wire.required(options, "with").unwrap())
    .unwrap()
    .map(sample => @wire.text(sample).unwrap())
  assert_eq(samples.length(), 3)
  assert_eq(samples[0], samples[2])
  assert_true(samples[0] != samples[1])
}

///|
test "Mean source rejects implicit inputs non-Graph names and forward references" {
  let options = ", weights: [1], support: {nodes: 1, edges: 1}, properties: {nodes: {p: 'exact_equal'}, edges: {}}"
  for samples in ["[]", "[n]", "[missing]"] {
    let result = classified_graph_source(
      graph_union_prefix() +
      "DATA combined = mean_graphs(with: " +
      samples +
      options +
      "); FROM combined |> node_rows() |> SELECT p",
    )
    assert_true(
      if samples == "[]" {
        result is Err(InvalidQuery)
      } else {
        result is Err(UnknownRelation)
      },
    )
  }
  for
    suffix in [
      "DATA combined = FROM g |> mean_graphs(with: [g]" +
      options +
      "); FROM combined |> node_rows() |> SELECT p",
      "FROM g |> mean_graphs(with: [g]" +
      options +
      ") |> node_rows() |> SELECT p",
    ] {
    assert_true(
      classified_graph_source(graph_union_prefix() + suffix)
      is Err(InvalidQuery),
      msg=suffix,
    )
  }
}
