///|
fn match_with_prefix() -> String {
  "WITH n AS (SELECT 1 AS node_key, 7 AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)))) "
}

///|
test "projected MATCH WITH has an independent ordinary Program control" {
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.match_data","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":false}},"rows":[{"node_key":1,"p":7}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"fields":["p"]},"as":"matched"},{"from":"matched","select":[{"value":"p"}],"as":"chosen"},{"from":"chosen","sort":[{"field":"value","dir":"asc","nulls":"first"}],"as":"sorted"}],"results":{"rows":{"from":"sorted","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed_with_evidence(
      control,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("independent MATCH WITH control requires no Source")
  }
  let actual = compile_with_set(
    match_with_prefix() +
    ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value) FROM chosen |> ORDER BY value",
  )
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
    NeedsInputs(_) => fail("projected MATCH WITH requires no Source")
  }
}

///|
test "projected MATCH WITH retains a complete independently authored lowering" {
  let actual = compile_with_set(
    match_with_prefix() +
    ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value) FROM chosen |> ORDER BY value",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_1"},"fields":["aql_keyed_identity_1","p"]},"as":"aql_keyed_seeds_4"},{"from":"aql_keyed_seeds_4","select":[{"value":"p"}],"as":"aql_script_cte_3"},{"from":"aql_script_cte_3","sort":[{"field":"value","dir":"asc","nulls":"first"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "MATCH WITH permits quoted names and ordinary Relation continuation" {
  for
    suffix in [
      ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node WHERE p > 0) |> SELECT a.p AS value) FROM chosen |> WHERE value > 1 |> SELECT * |> ORDER BY value",
      ", `picked rows` AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value) FROM `picked rows` |> SELECT value",
      ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node WHERE p > 9) |> SELECT a.p AS value) FROM chosen |> SELECT value",
    ] {
    let actual = compile_with_set(match_with_prefix() + suffix)
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
      NeedsInputs(_) => fail("MATCH WITH adds no acquisition")
    }
  }
}

///|
test "MATCH WITH still rejects implicit Graph element and star exports" {
  for projection in ["", " |> SELECT *"] {
    assert_true(
      match_with_compile(
        match_with_prefix() +
        ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node)" +
        projection +
        ") FROM chosen |> SELECT *",
      )
      is Err(UnsupportedProjection),
    )
  }
}

///|
test "MATCH WITH erases pattern scope without exposing private identity" {
  for reference in ["a.p", "g.p", "node_key", "aql_keyed_identity_1"] {
    assert_true(
      match_with_compile(
        match_with_prefix() +
        ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value) FROM chosen |> SELECT " +
        reference,
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=reference,
    )
  }
}

///|
test "MATCH WITH retains pure-body publication restrictions and nested producers" {
  assert_true(
    @query.parse_query_script(
      match_with_prefix() +
      ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value |> RESULT hidden) FROM chosen",
      syntax_limits(),
    )
    is Err({ issue: @query.Syntax("RESULT is not allowed in a producer body"), .. }),
  )
  for operator in ["INFER", "EFFECT"] {
    assert_true(
      @query.parse_query_script(
        match_with_prefix() +
        ", chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value |> " +
        operator +
        ") FROM chosen",
        syntax_limits(),
      )
      is Err(_),
    )
  }
  for text in [
    ", outer_rows AS (WITH chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value) SELECT value FROM chosen) SELECT value FROM outer_rows",
    "SELECT value FROM (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value)",
  ] {
    let actual = compile_with_set(match_with_prefix() + text)
    match @check.check_parsed_with_evidence(
      actual, graph_rows_environment(), None, [], graph_rows_check_limits(),
    ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("nested MATCH WITH adds no acquisition")
    }
  }
}

///|
fn match_with_compile(text : String) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  )
}

///|
test "independent public MATCH WITH controls and source use the normal checker" {
  for
    text in [
      "WITH n AS (SELECT 2 AS node_key, 7 AS p UNION ALL SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p, node_key)))), chosen AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value, a.node_key AS key) FROM chosen |> WHERE key > 0 |> SELECT value, key |> ORDER BY key |> RESULT matched",
      "WITH n AS (SELECT 2 AS node_key, 7 AS p UNION ALL SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p, node_key)))), chosen AS (FROM GRAPH g |> MATCH WALK (a:Node WHERE node_key > 9) |> SELECT a.p AS value, a.node_key AS key) FROM chosen |> WHERE key > 0 |> SELECT value, key |> ORDER BY key |> RESULT matched",
      "WITH n AS (SELECT 2 AS node_key, 7 AS p UNION ALL SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p, node_key)))), `picked rows` AS (FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value, a.node_key AS key) FROM `picked rows` |> SELECT * |> ORDER BY key |> RESULT matched",
      "WITH n AS (SELECT 2 AS node_key, 7 AS p UNION ALL SELECT 1 AS node_key, CAST(NULL AS FLOAT64) AS p), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p, node_key)))), chosen AS (FROM GRAPH g |> normalize_graph() |> MATCH WALK (a:Node) |> SELECT a.p AS value, a.node_key AS key) FROM chosen |> WHERE key > 0 |> SELECT value, key |> ORDER BY key |> RESULT matched",
      "WITH n AS (SELECT 1 AS node_key), e AS (SELECT 11 AS edge_key, 1 AS src, 1 AS dst UNION ALL SELECT 10 AS edge_key, 1 AS src, 1 AS dst), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES))), chosen AS (FROM GRAPH g |> MATCH p = TRAIL (:Node)-[:R]->{2,2}(:Node) |> SELECT PATH_LENGTH(p) AS value) FROM chosen |> WHERE value > 1 |> SELECT value |> ORDER BY value |> RESULT matched",
    ] {
    let actual = compile_with_set(text)
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
      NeedsInputs(_) => fail("Values-backed MATCH WITH adds no acquisition")
    }
  }
  for
    text in [
      (
        #|{"version":"actql/0.1","id":"fixture.match_data.nodes","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":2,"p":7},{"node_key":1,"p":null}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"},{"from":"node_key","to":"node_key"}]}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"fields":["p","node_key"]},"as":"matched"},{"from":"matched","select":[{"value":"p"},{"key":"node_key"}],"as":"chosen"},{"from":"chosen","filter":{"gt":[{"field":"key"},{"literal":0}]}},{"select":["value","key"]},{"sort":[{"field":"key","dir":"asc","nulls":"first"}],"as":"output"}],"results":{"out":{"from":"output","fields":["value","key"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
      ),
      (
        #|{"version":"actql/0.1","id":"fixture.match_data.empty","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":2,"p":7},{"node_key":1,"p":null}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"},{"from":"node_key","to":"node_key"}]}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Node","where":{"gt":[{"field":"node_key"},{"literal":9}]},"fields":["p","node_key"]},"as":"matched"},{"from":"matched","select":[{"value":"p"},{"key":"node_key"}],"as":"chosen"},{"from":"chosen","filter":{"gt":[{"field":"key"},{"literal":0}]}},{"select":["value","key"]},{"sort":[{"field":"key","dir":"asc","nulls":"first"}],"as":"output"}],"results":{"out":{"from":"output","fields":["value","key"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
      ),
      (
        #|{"version":"actql/0.1","id":"fixture.match_data.trail","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false}},"rows":[{"node_key":1}]},"as":"n"},{"values":{"schema":{"edge_key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"edge_key":11,"src":1,"dst":1},{"edge_key":10,"src":1,"dst":1}]},"as":"e"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[{"name":"E","from":"e","key":["edge_key"],"source":{"definition":"N","key":["src"],"references_key":["node_key"]},"target":{"definition":"N","key":["dst"],"references_key":["node_key"]},"labels":[{"name":"R","properties":{"mode":"no_properties"}}]}]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"bindings":{"identity":"element"},"fields":["element"]},"as":"seeds"},{"from":"g","traverse":{"start":{"from":"seeds","id":"element"},"direction":"out","min_hops":2,"max_hops":2,"edge_types":["R"],"path_mode":"trail","emit":"paths"},"as":"paths"},{"from":"paths","select":[{"value":"hop_count"}],"as":"chosen"},{"from":"chosen","filter":{"gt":[{"field":"value"},{"literal":1}]}},{"select":["value"]},{"sort":[{"field":"value","dir":"asc","nulls":"first"}],"as":"output"}],"results":{"out":{"from":"output","fields":["value"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
      ),
      (
        #|{"version":"actql/0.1","id":"fixture.match_data.reused","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":2,"p":20}]},"as":"n"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"},{"from":"node_key","to":"node_key"}]}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"fields":["p","node_key"]},"as":"matched"},{"from":"matched","select":[{"value":"p"},{"key":"node_key"}],"as":"chosen"},{"from":"chosen","filter":{"gt":[{"field":"key"},{"literal":0}]}},{"select":["value","key"]},{"sort":[{"field":"key","dir":"asc","nulls":"first"}],"as":"output"}],"results":{"out":{"from":"output","fields":["value","key"]},"original":{"from":"chosen","fields":["value","key"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}},"original":{"from":{"stage":"main","result":"original"}}}}
      ),
    ] {
    let expected = @program.parse(
      text,
      construction_limits().program,
      format=Json,
    ).unwrap()
    match
      @check.check_parsed_with_evidence(
        expected,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) =>
        fail("independent Values-backed control adds no acquisition")
    }
  }
}
