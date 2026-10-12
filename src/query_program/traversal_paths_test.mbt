///|
fn traversal_paths_source() -> String {
  "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))), seeds AS (FROM g |> node_rows() |> SELECT id AS element) FROM g |> traverse(start: {from: seeds, id: `element`}, direction: 'out', min_hops: 0, max_hops: 1, path_mode: 'trail', emit: 'paths', max_output_rows: 10) |> SELECT start_id, end_id, hop_count, node_ids, edge_ids"
}

///|
fn traversal_paths_expected() -> @program.Program {
  // Independently authored complete Program and ordered path fields. No
  // lowering output or runtime sample supplies this oracle.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"node_key":"aql_query_expr_0"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":[{"element":"id"}],"as":"aql_script_cte_3"},{"from":"aql_with_graph_2","traverse":{"start":{"from":"aql_script_cte_3","id":"element"},"direction":"out","min_hops":0,"max_hops":1,"path_mode":"trail","emit":"paths","max_output_rows":10},"as":"aql_sga_5"},{"from":"aql_sga_5","select":["start_id","end_id","hop_count","node_ids","edge_ids"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["start_id","end_id","hop_count","node_ids","edge_ids"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    NeedsInputs(_) => fail("WITH selector reuses a producer")
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
test "Graph traversal path WITH preserves declared arguments and current column scope" {
  let source = traversal_paths_source()
    .replace(old="seeds AS", new="`seed set` AS")
    .replace(old="from: seeds", new="from: `seed set`")
    .replace(old="FROM g |> traverse", new=", visited AS (FROM g |> traverse") +
    ") FROM visited |> WHERE hop_count >= 0 |> SELECT edge_ids, node_ids, hop_count |> ORDER BY hop_count"
  let program = compile_with_set(source)
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
  // Literal UTF-8 ranges belong to the final SELECT, not an earlier Graph field.
  for (field, end) in [("depth", 339), ("node_id", 341)] {
    let source = traversal_paths_source().replace(
      old="SELECT start_id, end_id, hop_count, node_ids, edge_ids",
      new="SELECT " + field,
    )
    let result = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    guard result
      is Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) else {
      fail("path output must reject node-only field: " + field)
    }
    assert_eq(@origin.kind(origin), @origin.Authored)
    let span = @origin.span(origin)
    assert_eq(span.start_byte, 334)
    assert_eq(span.end_byte, end)
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
test "Graph traversal path preserves precise common static refusals" {
  for
    (before, after) in [
      ("id: `element`", "id: `missing`"),
      ("max_hops: 1", "max_hops: 0"),
      ("path_mode: 'trail'", "path_mode: 'invented'"),
      ("max_output_rows: 10", "max_output_rows: 10, extra: true"),
    ] {
    if before == "id: `element`" {
      assert_true(
        classified_graph_source(traversal_paths_source().replace(old=before, new=after))
        is Err(UnknownColumn),
      )
      continue
    }
    expect_with_graph_static_refusal(
      traversal_paths_source().replace(old=before, new=after),
      expected=Some(
        if before == "max_hops: 1" {
          @pipeline.GraphMatch(Structure(InvalidCount))
        } else if before == "path_mode: 'trail'" {
          @pipeline.GraphMatch(Structure(InvalidBody))
        } else {
          @pipeline.InvalidBody
        },
      ),
    )
  }
}
