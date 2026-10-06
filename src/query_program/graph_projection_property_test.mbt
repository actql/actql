///|
fn graph_projection_property_context() -> Context {
  let values = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null},{"id":4,"payload":{"score":null}}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(values),
        visible_fields: ["id", "payload"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn graph_projection_property_source(tail : String) -> String {
  "DATA g = PROPERTY GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))); FROM GRAPH g |> MATCH WALK (a:Person) |> " +
  tail
}

///|
fn graph_projection_property_expected(
  with_filter? : Bool = false,
) -> @program.Program {
  // Handwritten ordinary Program: nullable property access is an expression,
  // while static label membership remains owned by match_nodes.
  let text =
    #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null},{"id":4,"payload":{"score":null}}]},"as":"aql_script_seed_2"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_seed_2","key":["id"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"payload","to":"payload"}]}}]}],"edges":[]},"as":"aql_data_1"},{"from":"aql_data_1","match_nodes":{"definition":"N","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","payload"],"label":"Person"},"as":"aql_keyed_seeds_3"},{"from":"aql_keyed_seeds_3","derive":{"aql_query_expr_1":{"property":{"name":"score","value":{"field":"payload"}}}}},{"select":["id",{"score":"aql_query_expr_1"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let text = if with_filter {
    text.replace(
      old="{\"from\":\"aql_keyed_seeds_3\",\"derive\":",
      new="{\"from\":\"aql_keyed_seeds_3\",\"filter\":{\"and\":[{\"not\":{\"is_null\":{\"field\":\"aql_keyed_identity_2\"}}},{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":10}]}]}},{\"derive\":",
    )
  } else {
    text
  }
  @program.parse(text, construction_limits().program, format=Json).unwrap()
}

///|
test "Graph projection property independent Program passes the ordinary checker" {
  match
    @check.check_parsed(
      graph_projection_property_expected(),
      graph_rows_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Values do not require acquisition")
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
  }
}

///|
test "Graph projection property lowers to an independent complete Program" {
  let actual = match
    compile_query_script(
      @query.parse_query_script(
        graph_projection_property_source(
          "SELECT a.id AS id, a.payload.score AS score",
        ),
        syntax_limits(),
      ).unwrap(),
      graph_projection_property_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(Expression(diagnostic)) => fail(@debug.to_string(diagnostic.issue))
    Err(_) => fail("unexpected lowering issue outside expression resolution")
  }
  assert_eq(semantic(actual), semantic(graph_projection_property_expected()))
}

///|
test "Graph projection property uses the same qualified quoted and local receiver slots" {
  for
    tail in [
      "SELECT a.id AS id, payload.score AS score", "SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`score` AS score",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(
        graph_projection_property_source(tail),
        syntax_limits(),
      ).unwrap(),
      graph_projection_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(graph_projection_property_expected()))
  }
}

///|
test "Graph projection property and identity macros share the ordinary expression tree" {
  let program = compile_query_script(
    @query.parse_query_script(
      graph_projection_property_source(
        "WHERE NODE_ID(a) IS NOT NULL AND a.payload.score > 10 |> SELECT a.id AS id, a.payload.score AS score",
      ),
      syntax_limits(),
    ).unwrap(),
    graph_projection_property_context(),
    construction_limits(),
  ).unwrap()
  let expected = semantic(graph_projection_property_expected(with_filter=true))
  assert_eq(semantic(program), expected)
  match
    @check.check_parsed(program, graph_rows_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Values do not require acquisition")
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
  }
}

///|
test "Graph projection property refuses foreign and removed receivers before checking" {
  for
    tail in [
      "SELECT other.payload.score AS score", "SELECT missing.score AS score", "SELECT a.id AS id |> WHERE payload.score > 0",
    ] {
    let result = compile_query_script(
      @query.parse_query_script(
        graph_projection_property_source(tail),
        syntax_limits(),
      ).unwrap(),
      graph_projection_property_context(),
      construction_limits(),
    )
    assert_true(
      result
      is Err(
        Expression({ issue: @expression.UnknownReference, origin: Some(_), })
      ),
      msg=tail,
    )
  }
}

///|
test "Graph projection property retains expression work limits" {
  let result = compile_query_script(
    @query.parse_query_script(
      graph_projection_property_source(
        "SELECT a.id AS id, a.payload.score AS score",
      ),
      syntax_limits(),
    ).unwrap(),
    graph_projection_property_context(),
    { ..construction_limits(), max_expression_work: 1, },
  )
  assert_true(result is Err(Expression({ issue: @expression.WorkLimit, .. })))
}
