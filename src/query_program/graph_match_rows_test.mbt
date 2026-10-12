///|
test "independent common Graph match control is already checked" {
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.graph_match","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":false}},"rows":[{"node_key":1,"p":7}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Person","where":{"gt":[{"field":"p"},{"literal":5}]},"fields":["p"]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["p"]}}}],"results":{"answer":{"from":{"stage":"main","result":"out"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
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
    NeedsInputs(_) => fail("The common control has no external input")
  }
}

///|
test "named Graph match has an independently authored complete Program" {
  let actual = compile_with_set(
    "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))) FROM g |> match_nodes(definition: 'N', label: 'Person', where: {gt: [{field: `p`}, {literal: 5}]}, fields: [`p`]) |> SELECT p",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","label":"Person","where":{"gt":[{"field":"p"},{"literal":5}]},"fields":["p"]},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["p"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
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
    NeedsInputs(_) => fail("A named Graph match does not acquire input")
  }
}

///|
test "named Graph match carries projection order and identity roles to the common owner" {
  for
    suffix in [
      "FROM g |> match_nodes(definition: 'n', bindings: {identity: `element`}, where: {literal: true}, fields: [`name`, `element`]) |> SELECT name, element |> ORDER BY name",
      ", selected AS (FROM g |> normalize_graph() |> match_edges(definition: 'E', label: 'r', bindings: {identity: `edge`, source: `source`, target: `target`}, fields: [`target`, `edge`, `source`])) FROM selected |> SELECT target, edge, source",
    ] {
    let actual = compile_with_set(graph_rows_prefix() + suffix)
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
      NeedsInputs(_) => fail("A matched Relation reuses its Graph producer")
    }
  }
}

///|
test "named Graph match retains precise common static refusals" {
  // The common match owner fixes these causes before binding demand pruning.
  for
    (call, expected) in [
      (
        "match_nodes(definition: 'N', where: {literal: true}, fields: [`missing`])",
        @pipeline.GraphMatch(Structure(UnknownMatchField("missing"))),
      ),
      (
        "match_nodes(definition: 'missing', where: {literal: true}, fields: [`name`])",
        @pipeline.GraphMatch(Structure(InvalidName("missing"))),
      ),
      (
        "match_nodes(definition: 'N', label: 'missing', where: {literal: true}, fields: [`name`])",
        @pipeline.GraphMatch(Structure(InvalidName("missing"))),
      ),
      (
        "match_nodes(definition: 'N', fields: [`name`])",
        @pipeline.GraphMatch(Structure(InvalidBody)),
      ),
      (
        "match_nodes(definition: 'N', where: {literal: 1}, fields: [`name`])",
        @pipeline.GraphMatch(ExpectedBoolean),
      ),
      (
        "match_nodes(definition: 'N', where: {literal: true}, fields: [`name`, `name`])",
        @pipeline.GraphMatch(Structure(DuplicateMatchField("name"))),
      ),
      (
        "match_nodes(definition: 'N', bindings: {identity: `name`}, where: {literal: true}, fields: [`name`])",
        @pipeline.GraphMatch(Structure(ScopeCollision("name"))),
      ),
      (
        "match_nodes(definition: 'N', where: {literal: true}, fields: [`name`], extra: true)",
        @pipeline.GraphMatch(Structure(Decode(UnknownField))),
      ),
      (
        "match_edges(definition: 'E', bindings: {source: `src`}, fields: [`src`], types: [1])",
        @pipeline.GraphMatch(Structure(Decode(WrongType))),
      ),
    ] {
    expect_with_graph_static_refusal(
      graph_rows_prefix() + "FROM g |> " + call,
      expected=Some(expected),
    )
  }
}

///|
test "named Graph match refuses undefined output shape and subsequent Graph calls" {
  for
    suffix in [
      "FROM g |> match_nodes(definition: 'N', where: {literal: true})", "FROM g |> match_nodes(definition: 'N', where: {literal: true}, fields: [])",
      "FROM g |> match_nodes(definition: 'N', where: {literal: true}, fields: [`name`]) |> node_rows()",
      "FROM n |> match_nodes(definition: 'N', where: {literal: true}, fields: [`name`])",
    ] {
    let parsed = @query.parse_query_script(
      graph_rows_prefix() + suffix,
      syntax_limits(),
    ).unwrap()
    let actual = compile_query_script(
      parsed,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    if suffix.has_prefix("FROM n") || suffix.has_suffix("|> node_rows()") {
      assert_true(actual is Err(InvalidQuery), msg=suffix)
    } else {
      assert_true(actual is Err(UnsupportedGraph), msg=suffix)
    }
  }
}

///|
test "Graph match field role rejects numeric entries before lowering" {
  assert_true(
    @query.parse_query_script(
      graph_rows_prefix() +
      "FROM g |> match_nodes(definition: 'N', where: {literal: true}, fields: [name, 1])",
      syntax_limits(),
    ) is Err({ issue: WrongQueryForm, .. }),
  )
}
