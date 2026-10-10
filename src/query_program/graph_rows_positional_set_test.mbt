///|
test "Graph row positional set operands retain the named expression control" {
  let prefix = "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) EDGE TABLES (n AS E KEY (node_key) SOURCE KEY (node_key) REFERENCES N DESTINATION KEY (node_key) REFERENCES N LABEL R PROPERTIES (p))); "
  for operation in ["node_rows", "edge_rows"] {
    for output_alias in [" AS other", ""] {
      let source = prefix +
        "FROM n |> SELECT p AS value |> UNION ALL (FROM g |> " +
        operation +
        "() |> SELECT p + 1" +
        output_alias +
        ") |> ORDER BY value"
      let program = match
        compile_query_script(
          @query.parse_query_script(source, syntax_limits()).unwrap(),
          { ..fixture_context(), inputs: [], },
          construction_limits(),
        ) {
        Ok(program) => program
        Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
        Err(UnsupportedGraph) => fail(source + ": UnsupportedGraph")
        Err(_) => fail(source + ": another lowering rejection")
      }
      match
        @check.check_parsed_with_evidence(
          program,
          graph_rows_environment(),
          None,
          [],
          graph_rows_check_limits(),
        ) {
        Checked(_) => ()
        Rejected(issue) => graph_rows_rejected(issue)
        NeedsInputs(_) => fail("Graph row set uses existing logical producers")
      }
      // The first Relation owns the public name and ordinal alignment. The
      // independent values are seven and eight on either bridge.
      assert_true(semantic(program).contains("\"fields\":[\"value\"]"))
    }
  }
}

///|
test "Graph row anonymous fields do not satisfy BY NAME or later ORDER" {
  let prefix = "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p))); "
  for
    (tail, by_name) in [
      (
        "FROM n |> SELECT p AS value |> UNION ALL BY NAME (FROM g |> node_rows() |> SELECT p + 1)",
        true,
      ),
      (
        "FROM n |> SELECT p AS value |> UNION ALL (FROM g |> node_rows() |> SELECT p + 1) |> ORDER BY aql_set_anonymous_4",
        false,
      ),
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(prefix + tail, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    if by_name {
      assert_true(actual is Err(UnsupportedProjection))
    } else {
      assert_true(
        actual is Err(Expression({ issue: @expression.UnknownReference, .. })),
      )
    }
  }
}

///|
test "Graph row set heads reach the same ordinary set owner in root and DATA" {
  let prefix = "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p))); "
  let body = "FROM g |> node_rows() |> SELECT p AS value |> UNION ALL (FROM n |> SELECT p + 1 AS other)"
  for
    suffix in [
      body + " |> ORDER BY value",
      "DATA combined = " + body + "; FROM combined |> ORDER BY value",
    ] {
    let program = match
      compile_query_script(
        @query.parse_query_script(prefix + suffix, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedGraph) => fail(suffix + ": UnsupportedGraph")
      Err(_) => fail(suffix + ": another rejection")
    }
    match
      @check.check_parsed_with_evidence(
        program,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => graph_rows_rejected(issue)
      NeedsInputs(_) => fail("Graph row head has no external acquisition")
    }
  }
}
