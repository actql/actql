///|
fn with_graph_alias_prefix() -> String {
  "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)))) "
}

///|
test "Graph row aliases fail with one static reason before or after MATCH" {
  for
    tail in [
      "FROM GRAPH g AS row_alias |> MATCH WALK (a:Node) |> SELECT a.p", "FROM GRAPH g row_alias |> node_rows() |> SELECT p",
      "FROM g AS row_alias |> MATCH WALK (a:Node) |> SELECT a.p", "FROM g row_alias |> node_rows() |> SELECT p",
      "FROM g |> AS row_alias |> MATCH WALK (a:Node) |> SELECT a.p", "FROM g |> MATCH WALK (a:Node) |> AS row_alias |> SELECT a.p",
      "FROM g |> AS row_alias |> node_rows() |> SELECT p", ", renamed AS (FROM g |> AS row_alias) FROM renamed |> node_rows() |> SELECT p",
    ] {
    let script = @query.parse_query_script(
      with_graph_alias_prefix() + tail,
      syntax_limits(),
    ).unwrap()
    let actual = compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    assert_true(actual is Err(RangeAliasRequiresRelation), msg=tail)
  }
}

///|
test "WITH producer alias and row alias after a Graph bridge remain valid" {
  for
    tail in [
      ", renamed AS (FROM g) FROM renamed |> node_rows() |> AS r |> SELECT r.p",
      "FROM g |> node_rows() |> AS r |> SELECT r.p", "FROM g |> MATCH WALK (a:Node) |> SELECT a.p AS p |> AS r |> SELECT r.p",
    ] {
    let program = compile_with_set(with_graph_alias_prefix() + tail)
    let body = semantic(program)
    assert_eq(body.split("\"graph\":{").length(), 2)
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
      NeedsInputs(_) => fail("WITH alias introduces no input acquisition")
    }
  }
}
