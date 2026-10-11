///|
fn graph_delta_source_compile(text : String) -> @program.Program raise {
  match
    compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedGraph) => fail("UnsupportedGraph")
    Err(_) => fail("Unexpected lowering failure")
  }
}

///|
fn graph_delta_source_prefix() -> String {
  "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))), changes AS (FROM g |> node_rows() |> SELECT id AS delta) "
}

///|
fn graph_delta_source_expected() -> @program.Program {
  // A typed identity supplies an ordinary non-null JSON column for Check.
  // It is not a Delta; exact Delta shape/base/target admission is runtime-owned.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","node_rows":true,"as":"aql_sga_4"},{"from":"aql_sga_4","select":[{"delta":"id"}],"as":"aql_script_cte_3"},{"from":"aql_with_graph_2","apply_graph_delta":{"with":"aql_script_cte_3","field":"delta"},"as":"aql_sga_5"},{"from":"aql_sga_5","node_rows":true,"as":"aql_sga_6"},{"from":"aql_sga_6","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph Delta source independent Program passes the ordinary checker" {
  match
    @check.check_parsed_with_evidence(
      graph_delta_source_expected(),
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("Graph row projection requires no acquisition")
  }
}

///|
test "Graph Delta source matches an independent complete Program" {
  let actual = graph_delta_source_compile(
    graph_delta_source_prefix() +
    "FROM g |> apply_graph_delta(with: changes, field: 'delta') |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(actual), semantic(graph_delta_source_expected()))
}

///|
test "Graph Delta source preserves quoted WITH bindings and MATCH continuation" {
  for
    tail in [
      ", `saved changes` AS (FROM changes), applied AS (FROM g |> apply_graph_delta(field: 'delta', with: `saved changes`)) FROM applied |> node_rows() |> SELECT node_key, p",
      "FROM GRAPH g |> normalize_graph() |> apply_graph_delta(with: changes, field: 'delta') |> MATCH WALK (a:Person) |> SELECT a.p AS p",
    ] {
    let actual = graph_delta_source_compile(graph_delta_source_prefix() + tail)
    let body = semantic(actual)
    assert_eq(body.split("\"graph\":").length(), 2)
    assert_eq(body.split("\"apply_graph_delta\":").length(), 2)
    assert_true(body.contains("\"field\":\"delta\""))
    match
      @check.check_parsed_with_evidence(
        actual,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("WITH references must not add acquisition")
    }
  }
}

///|
test "Graph Delta source keeps invalid argument bodies at the common checker" {
  for
    call in [
      "apply_graph_delta()", "apply_graph_delta(with: changes)", "apply_graph_delta(with: changes, field: 'missing')",
      "apply_graph_delta(with: changes, field: 1)", "apply_graph_delta(with: changes, field: 'delta', extra: true)",
    ] {
    let expected : @pipeline.IssueKind = match call {
      "apply_graph_delta()" | "apply_graph_delta(with: changes)"
      | "apply_graph_delta(with: changes, field: 'delta', extra: true)" =>
        @pipeline.InvalidBody
      "apply_graph_delta(with: changes, field: 'missing')" =>
        @pipeline.Graph(UnknownDeltaField("missing"))
      "apply_graph_delta(with: changes, field: 1)" => @pipeline.Decode(WrongType)
      _ => fail("undeclared malformed Delta control")
    }
    // The unified WITH owner runs the ordinary common static checker before
    // returning a complete Program. Do not fabricate an invalid Program.
    expect_with_graph_static_refusal(
      graph_delta_source_prefix() +
      "FROM g |> " +
      call +
      " |> node_rows() |> SELECT node_key",
      expected=Some(expected),
    )
  }
}

///|
test "Graph Delta source rejects foreign names and a second Carrier transition" {
  for
    (tail, reference) in [
      (
        "FROM g |> apply_graph_delta(with: missing, field: 'delta') |> node_rows()",
        "missing",
      ),
      (
        "FROM g |> apply_graph_delta(with: g, field: 'delta') |> node_rows()", "g",
      ),
      (
        ", applied AS (FROM g |> apply_graph_delta(with: later, field: 'delta')), later AS (FROM changes) FROM applied |> node_rows()",
        "later",
      ),
    ] {
    let script = @query.parse_query_script(
      graph_delta_source_prefix() + tail,
      syntax_limits(),
    ).unwrap()
    assert_true(
      exact_unresolved_relation(
        compile_query_script(
          script,
          { ..fixture_context(), inputs: [], },
          construction_limits(),
        ),
        [(reference, false)],
      ),
      msg=tail,
    )
  }
  let script = @query.parse_query_script(
    graph_delta_source_prefix() +
    "FROM g |> node_rows() |> apply_graph_delta(with: changes, field: 'delta')",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(InvalidQuery),
  )
  assert_true(
    @query.parse_query_script(
      graph_delta_source_prefix() +
      "FROM g |> apply_graph_delta(with: 'changes', field: 'delta') |> node_rows()",
      syntax_limits(),
    )
    is Err({ issue: Syntax("Expected identifier"), .. }),
  )
}
