///|
fn traversal_paths_source() -> String {
  "DATA n = SELECT 1 AS node_key; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)); DATA seeds = FROM g |> node_rows() |> SELECT id AS element; FROM g |> traverse(start: {from: seeds, id: 'element'}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'paths', max_output_rows: 10) |> SELECT start_id, end_id, hop_count, node_ids, edge_ids"
}

///|
fn traversal_paths_expected() -> @program.Program {
  // Independently authored complete Program and ordered path fields. No
  // lowering output or runtime sample supplies this oracle.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"node_key":"aql_query_expr_0"}],"as":"aql_data_0"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":[{"element":"id"}],"as":"aql_data_3"},{"from":"aql_data_2","traverse":{"start":{"from":"aql_data_3","id":"element"},"direction":"out","min_hops":0,"max_hops":1,"path_mode":"trail","emit":"paths","max_output_rows":10},"as":"aql_sga_5"},{"from":"aql_sga_5","select":["start_id","end_id","hop_count","node_ids","edge_ids"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["start_id","end_id","hop_count","node_ids","edge_ids"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph traversal path independent Program passes the ordinary checker" {
  match
    @check.check_parsed_with_evidence(
      traversal_paths_expected(),
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("DATA selector reuses a producer")
  }
}

///|
test "Graph traversal path source retains an independent complete Program" {
  let actual = match
    compile_query_script(
      @query.parse_query_script(traversal_paths_source(), syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedGraph) => fail("UnsupportedGraph")
    Err(_) => fail("unexpected lowering refusal")
  }
  assert_eq(semantic(actual), semantic(traversal_paths_expected()))
}

///|
test "Graph traversal path DATA preserves declared arguments and current column scope" {
  let source = traversal_paths_source()
    .replace(old="DATA seeds", new="DATA `seed set`")
    .replace(old="from: seeds", new="from: `seed set`")
    .replace(old="FROM g |> traverse", new="DATA visited = FROM g |> traverse") +
    "; FROM visited |> WHERE hop_count >= 0 |> SELECT edge_ids, node_ids, hop_count |> ORDER BY hop_count"
  let program = compile_data_set(source)
  let body = semantic(program)
  assert_eq(body.split("\"traverse\":").length(), 2)
  assert_true(body.contains("\"max_output_rows\":10"))
  assert_true(
    body.contains("\"fields\":[\"edge_ids\",\"node_ids\",\"hop_count\"]"),
  )
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("A bound path producer is not acquired again")
  }
}

///|
test "Graph traversal path fields cannot be confused with node emission fields" {
  for field in ["depth", "node_id"] {
    let source = traversal_paths_source().replace(
      old="SELECT start_id, end_id, hop_count, node_ids, edge_ids",
      new="SELECT " + field,
    )
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=field,
    )
  }
}

///|
test "Graph traversal path emission remains explicit and static" {
  for value in ["'invented'", "@emission"] {
    let source = traversal_paths_source().replace(old="'paths'", new=value)
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedGraph),
      msg=value,
    )
  }
  let omitted = traversal_paths_source().replace(old=", emit: 'paths'", new="")
  assert_true(
    compile_query_script(
      @query.parse_query_script(omitted, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnsupportedGraph),
  )
}

///|
test "Graph traversal path preserves malformed arguments for common refusal" {
  for
    (before, after) in [
      ("id: 'element'", "id: 'missing'"),
      ("max_hops: 1", "max_hops: 0"),
      ("path_mode: 'trail'", "path_mode: 'invented'"),
      ("max_output_rows: 10", "max_output_rows: 10, extra: true"),
    ] {
    let program = compile_data_set(
      traversal_paths_source().replace(old=before, new=after),
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
      msg=after,
    )
  }
}
