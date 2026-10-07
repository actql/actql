///|
fn edge_predicate_nodes() -> String {
  (
    #|{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]}}
  )
}

///|
fn edge_predicate_links() -> String {
  (
    #|{"values":{"schema":{"edge_id":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false},"weight":{"type":"number","nullable":true},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"edge_id":10,"src":1,"dst":1,"weight":10,"payload":{"score":10}},{"edge_id":11,"src":1,"dst":1,"weight":20,"payload":{"score":20}},{"edge_id":12,"src":1,"dst":1,"weight":null,"payload":null}]}}
  )
}

///|
fn edge_predicate_context() -> Context {
  let inputs : Array[Input] = []
  for
    (name, text, fields) in [
      ("vertices", edge_predicate_nodes(), ["id"]),
      (
        "links",
        edge_predicate_links(),
        ["edge_id", "src", "dst", "weight", "payload"],
      ),
    ] {
    let value = @wire.admit(
      @source.parse_json(
        text[:text.length() - 1].to_owned() + ",\"as\":\"" + name + "\"}",
        construction_limits().source.source,
      ).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    inputs.push({
      relation: [{ value: name, quoted: false, }],
      name,
      source: GeneratedValues(value),
      visible_fields: fields,
      graph_bindings: [],
    })
  }
  { ..fixture_context(), inputs, }
}

///|
fn edge_predicate_prefix() -> String {
  "DATA g = PROPERTY GRAPH (NODE TABLES (vertices AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (links AS E KEY (edge_id) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R PROPERTIES (weight, payload))); "
}

///|
fn edge_predicate_compile(edge : String) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(
      edge_predicate_prefix() +
      "FROM GRAPH g |> MATCH p = WALK (:Node)" +
      edge +
      "(:Node) |> SELECT PATH_LENGTH(p) AS depth",
      syntax_limits(),
    ).unwrap(),
    edge_predicate_context(),
    construction_limits(),
  )
}

///|
fn checked_edge_predicate_compile(edge : String) -> @program.Program raise {
  match edge_predicate_compile(edge) {
    Ok(program) => program
    Err(Expression(issue)) => fail(@debug.to_string(issue.issue))
    Err(UnknownColumn) => fail("UnknownColumn")
    Err(UnsupportedGraph) => fail("UnsupportedGraph")
    Err(InvalidContext) => fail("InvalidContext")
    Err(_) => fail("Other lowering failure")
  }
}

///|
fn edge_predicate_expected(
  predicate : String,
  bounded : Bool,
) -> @program.Program {
  // Handwritten complete Program. Only the declared predicate and traversal
  // shape vary; no compiler output supplies a slot, argument or expected body.
  let traversal = if bounded {
    "\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"edge_types\":[\"R\"],\"edge_where\":" +
    predicate
  } else {
    "\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"R\"],\"edge_where\":" +
    predicate +
    "}]"
  }
  let nodes = edge_predicate_nodes()
  let links = edge_predicate_links()
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    nodes[:nodes.length() - 1].to_owned() +
    ",\"as\":\"aql_script_seed_3\"}," +
    links[:links.length() - 1].to_owned() +
    ",\"as\":\"aql_script_seed_4\"}," +
    (
      #|{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_seed_3","key":["id"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[{"name":"E","from":"aql_script_seed_4","key":["edge_id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"weight","to":"weight"},{"from":"payload","to":"payload"}]}}]}]},"as":"aql_data_2"},{"from":"aql_data_2","match_nodes":{"definition":"N","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_0"},"fields":["aql_keyed_identity_0"],"label":"Node"},"as":"aql_keyed_seeds_5"},{"from":"aql_data_2","traverse":{"start":{"from":"aql_keyed_seeds_5","id":"aql_keyed_identity_0"},"path_mode":"walk","emit":"paths",
    ) +
    traversal +
    (
      #|},"as":"aql_keyed_paths_6"},{"from":"aql_keyed_paths_6","derive":{"aql_query_expr_0":{"field":"hop_count"}}},{"select":[{"depth":"aql_query_expr_0"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["depth"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent edge predicate Program passes the ordinary checker" {
  for bounded in [false, true] {
    let expected = edge_predicate_expected(
      "{\"gt\":[{\"field\":\"weight\"},{\"literal\":10}]}", bounded,
    )
    match
      @check.check_parsed(
        expected,
        graph_rows_environment(),
        None,
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("Graph predicates reuse admitted producer inputs")
    }
  }
}

///|
test "fixed edge WHERE preserves its predicate in the complete ordinary Program" {
  let expected = edge_predicate_expected(
    "{\"gt\":[{\"field\":\"weight\"},{\"literal\":10}]}", false,
  )
  assert_eq(
    semantic(checked_edge_predicate_compile("-[:R WHERE weight > 10]->")),
    semantic(expected),
  )
}

///|
test "bounded edge WHERE preserves zero and maximum hop bounds" {
  let expected = edge_predicate_expected(
    "{\"gt\":[{\"field\":\"weight\"},{\"literal\":10}]}", true,
  )
  assert_eq(
    semantic(checked_edge_predicate_compile("-[:R WHERE weight > 10]->{0,2}")),
    semantic(expected),
  )
}

///|
test "edge property maps quoted names and nullable object receivers preserve values" {
  for
    (edge, predicate) in [
      (
        "-[:R {weight: 20}]->", "{\"eq\":[{\"field\":\"weight\"},{\"literal\":20}]}",
      ),
      (
        "-[:R WHERE `WEIGHT` > 10]->", "{\"gt\":[{\"field\":\"weight\"},{\"literal\":10}]}",
      ),
      ("-[:R WHERE weight IS NULL]->", "{\"is_null\":{\"field\":\"weight\"}}"),
      (
        "-[:R WHERE payload.score > 10]->", "{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":10}]}",
      ),
    ] {
    let expected = edge_predicate_expected(predicate, false)
    assert_eq(
      semantic(checked_edge_predicate_compile(edge)),
      semantic(expected),
    )
    match
      @check.check_parsed(
        expected,
        graph_rows_environment(),
        None,
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) =>
        fail("Predicate values stay in the existing expression path")
    }
  }
}

///|
test "edge predicates refuse foreign receivers and projection names during lowering" {
  for predicate in ["other.weight > 0", "missing.score > 0", "depth > 0"] {
    assert_true(
      edge_predicate_compile("-[:R WHERE " + predicate + "]->")
      is Err(
        Expression({ issue: @expression.UnknownReference, origin: Some(_), })
      ),
      msg=predicate,
    )
  }
  assert_true(
    edge_predicate_compile("-[:R {missing: 20}]->") is Err(UnknownColumn),
  )
  assert_true(
    edge_predicate_compile("-[e:R WHERE e.weight > 0]->")
    is Err(UnsupportedGraph),
  )
}

///|
test "invalid edge property types belong to the common traversal checker" {
  for
    predicate in ["payload.missing > 0", "weight.score > 0", "weight = 'high'"] {
    let program = checked_edge_predicate_compile(
      "-[:R WHERE " + predicate + "]->",
    )
    guard @check.check_parsed(
        program,
        graph_rows_environment(),
        None,
        graph_rows_check_limits(),
      )
      is Rejected(diagnostic) else {
      fail("Invalid edge property typing must be rejected")
    }
    guard @check.diagnostic_cause(diagnostic)
      is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
      fail("Edge predicate typing belongs to the ordinary pipeline")
    }
    assert_true(issue.kind is @pipeline.GraphMatch(_))
  }
}

///|
test "edge predicates retain expression work bounds" {
  let source = edge_predicate_prefix() +
    "FROM GRAPH g |> MATCH p = WALK ()-[:R WHERE payload.score > 10]->() |> SELECT PATH_LENGTH(p) AS depth"
  let actual = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    edge_predicate_context(),
    { ..construction_limits(), max_expression_work: 1, },
  )
  assert_true(actual is Err(Expression({ issue: @expression.WorkLimit, .. })))
}
