///|
fn graph_hop_node_context() -> Context {
  let inputs : Array[Input] = []
  for
    (name, text) in [
      (
        "objects", "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}},\"rows\":[{\"id\":1,\"payload\":{\"score\":0}},{\"id\":2,\"payload\":{\"score\":10}},{\"id\":3,\"payload\":{\"score\":20}},{\"id\":4,\"payload\":null}]},\"as\":\"objects\"}",
      ),
      (
        "links", "{\"values\":{\"schema\":{\"key\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"key\":10,\"src\":1,\"dst\":2},{\"key\":11,\"src\":1,\"dst\":3},{\"key\":12,\"src\":1,\"dst\":4},{\"key\":13,\"src\":3,\"dst\":2}]},\"as\":\"links\"}",
      ),
    ] {
    let values = @wire.admit(
      @source.parse_json(text, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    inputs.push({
      relation: [{ value: name, quoted: false, }],
      name,
      source: GeneratedValues(values),
      visible_fields: if name == "objects" {
        ["id", "payload"]
      } else {
        ["key", "src", "dst"]
      },
      graph_bindings: [],
    })
  }
  { ..fixture_context(), inputs, }
}

///|
fn graph_hop_node_source(pattern : String) -> String {
  "WITH g AS (GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Node PROPERTIES ALL COLUMNS) EDGE TABLES (links AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES))) FROM GRAPH g |> MATCH p = WALK " +
  pattern +
  " |> SELECT PATH_LENGTH(p) AS depth"
}

///|
fn graph_hop_node_expected() -> @program.Program {
  // Authored from the existing per-hop predicate contract, without compiler output.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":1,"payload":{"score":0}},{"id":2,"payload":{"score":10}},{"id":3,"payload":{"score":20}},{"id":4,"payload":null}]},"as":"aql_script_seed_3"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":2},{"key":11,"src":1,"dst":3},{"key":12,"src":1,"dst":4},{"key":13,"src":3,"dst":2}]},"as":"aql_script_seed_4"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_seed_3","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"aql_script_seed_4","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"no_properties"}}]}]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","label":"Node","where":{"eq":[{"field":"id"},{"literal":1}]},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","payload"]},"as":"aql_keyed_seeds_5"},{"from":"aql_with_graph_2","traverse":{"start":{"from":"aql_keyed_seeds_5","id":"aql_keyed_identity_2"},"path_mode":"walk","emit":"paths","hops":[{"direction":"out","edge_types":["R"],"node_where":{"gt":[{"property":{"name":"score","value":{"field":"payload"}}},{"literal":10}]}}]},"as":"aql_keyed_paths_6"},{"from":"aql_keyed_paths_6","derive":{"aql_query_expr_0":{"field":"hop_count"}}},{"select":[{"depth":"aql_query_expr_0"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["depth"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph hop node independent Program passes the ordinary checker" {
  match
    @check.check_parsed_with_evidence(
      graph_hop_node_expected(),
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Bound Values require no acquisition")
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
  }
}

///|
test "fixed Graph hop node predicate preserves its independent complete Program" {
  let program = compile_query_script(
    @query.parse_query_script(
      graph_hop_node_source(
        "(a:Node WHERE id = 1)-[:R]->(b:Node WHERE b.payload.score > 10)",
      ),
      syntax_limits(),
    ).unwrap(),
    graph_hop_node_context(),
    construction_limits(),
  )
  let program = match program {
    Ok(program) => program
    Err(UnsupportedGraph) =>
      fail("UnsupportedGraph: fixed hop node condition is not connected")
    Err(_) => fail("unexpected lowering rejection")
  }
  assert_eq(semantic(program), semantic(graph_hop_node_expected()))
}

///|
test "fixed Graph hop node predicate preserves local anonymous and quoted receivers" {
  for
    target in [
      "(:Node WHERE payload.score > 10)", "(b:Node WHERE `B`.`PAYLOAD`.`score` > 10)",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(
        graph_hop_node_source("(a:Node WHERE id = 1)-[:R]->" + target),
        syntax_limits(),
      ).unwrap(),
      graph_hop_node_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(graph_hop_node_expected()))
  }
}

///|
fn graph_hop_node_compile(pattern : String) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(graph_hop_node_source(pattern), syntax_limits()).unwrap(),
    graph_hop_node_context(),
    construction_limits(),
  )
}

///|
test "Graph hop node predicates are attached to their authored fixed hop" {
  let program = graph_hop_node_compile(
    "(a:Node WHERE id = 1)-[:R]->(b:Node WHERE payload.score > 10)-[:R]->(c:Node {id: 2})",
  ).unwrap()
  assert_true(
    semantic(program).contains(
      "\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"R\"],\"node_where\":{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":10}]}},{\"direction\":\"out\",\"edge_types\":[\"R\"],\"node_where\":{\"eq\":[{\"field\":\"id\"},{\"literal\":2}]}}]",
    ),
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
    NeedsInputs(_) => fail("Bound Values require no acquisition")
  }
}

///|
test "Graph hop node predicates retain incoming direction and ordinary NULL expressions" {
  for
    pattern in [
      "(a:Node WHERE id = 2)<-[:R]-(b:Node WHERE payload.score > 10)", "(a:Node WHERE id = 1)-[:R]->(b:Node WHERE payload.score IS NULL)",
    ] {
    let program = graph_hop_node_compile(pattern).unwrap()
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
      NeedsInputs(_) => fail("Bound Values require no acquisition")
    }
  }
}

///|
test "Graph hop node constraints do not acquire another node variable scope" {
  for predicate in ["a.payload.score > 10", "missing.score > 10", "chosen > 10"] {
    assert_true(
      graph_hop_node_compile(
        "(a:Node WHERE id = 1)-[:R]->(b:Node WHERE " + predicate + ")",
      )
      is Err(
        Expression({ issue: @expression.UnknownReference, origin: Some(_), })
      ),
    )
  }
}

///|
test "Graph hop member failures remain common checker obligations" {
  for predicate in ["payload.missing > 0", "id.score > 0"] {
    let kind = with_graph_predicate_refusal(
      graph_hop_node_compile(
        "(a:Node WHERE id = 1)-[:R]->(b:Node WHERE " + predicate + ")",
      ),
    )
    if predicate == "payload.missing > 0" {
      assert_true(kind is @pipeline.GraphMatch(Typing(UnknownField("missing"))))
    } else {
      assert_true(kind is @pipeline.GraphMatch(Typing(TypeMismatch("closed object receiver"))))
    }
  }
}

///|
test "quantified terminal conditions are not rewritten as every-hop conditions" {
  assert_true(
    graph_hop_node_compile(
      "(a:Node WHERE id = 1)-[:R]->{2,2}(b:Node WHERE payload.score > 10)",
    )
    is Err(UnsupportedGraph),
  )
}

///|
fn graph_hop_definition_prefix(extra? : Bool = false) -> String {
  let prefix = "WITH n AS (SELECT 1 AS id, 20 AS score), e AS (SELECT 10 AS key, 1 AS src, 1 AS dst), g AS (GRAPH (NODE TABLES (n AS S KEY (id) LABEL Start NO PROPERTIES, n AS T KEY (id) LABEL Target PROPERTIES (score)"
  let nodes = if extra {
    ", n AS U KEY (id) LABEL Other NO PROPERTIES"
  } else {
    ""
  }
  let edges = if extra {
    ", e AS F KEY (key) SOURCE KEY (src) REFERENCES S DESTINATION KEY (dst) REFERENCES U LABEL R NO PROPERTIES"
  } else {
    ""
  }
  prefix +
  nodes +
  ") EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES S DESTINATION KEY (dst) REFERENCES T LABEL R NO PROPERTIES" +
  edges +
  "))) "
}

///|
test "Graph hop scope uses reached definitions rather than the start schema" {
  let program = compile_with_set(
    graph_hop_definition_prefix() +
    "FROM GRAPH g |> MATCH p = WALK (:Start)-[:R]->(b:Target WHERE b.score > 10) |> SELECT PATH_LENGTH(p) AS depth",
  )
  assert_true(
    semantic(program).contains(
      "\"node_where\":{\"gt\":[{\"field\":\"score\"},{\"literal\":10}]}",
    ),
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
    NeedsInputs(_) => fail("Bound Values require no acquisition")
  }
}

///|
test "Graph hop scope does not invent property presence in other reached definitions" {
  expect_with_graph_static_refusal(
    graph_hop_definition_prefix(extra=true) +
    "FROM GRAPH g |> MATCH p = WALK (:Start)-[:R]->(b WHERE b.score > 10) |> SELECT PATH_LENGTH(p) AS depth",
    expected=Some(@pipeline.GraphMatch(UnknownField("score"))),
  )
  let parsed = @query.parse_query_script(
    graph_hop_definition_prefix(extra=true) +
    "FROM GRAPH g |> MATCH p = WALK (:Start)-[:R]->(:Target) |> SELECT PATH_LENGTH(p) AS depth",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      parsed,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnsupportedGraph),
  )
}

///|
test "Graph fixed hop retains both node and edge predicates after integration" {
  let source = graph_hop_node_source(
    "(a:Node WHERE id = 1)-[:R WHERE key = 10]->(b:Node WHERE payload.score > 10)",
  ).replace(old="LABEL R NO PROPERTIES", new="LABEL R PROPERTIES (key)")
  let program = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    graph_hop_node_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(program)
  assert_true(
    body.contains(
      "\"edge_where\":{\"eq\":[{\"field\":\"key\"},{\"literal\":10}]}",
    ),
  )
  assert_true(
    body.contains(
      "\"node_where\":{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":10}]}",
    ),
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
    NeedsInputs(_) => fail("Bound Values require no acquisition")
  }
}
