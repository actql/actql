///|
fn graph_property_predicate_context() -> Context {
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
fn graph_property_predicate_source(
  pattern : String,
  selection? : String = "a.id",
  output? : String = "id",
) -> String {
  "DATA g = PROPERTY GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))); FROM GRAPH g |> MATCH WALK " +
  pattern +
  " |> SELECT " +
  selection +
  " AS " +
  output
}

///|
fn graph_property_predicate_expected() -> @program.Program {
  // Independent ordinary Program, not a snapshot of compiler output.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null},{"id":4,"payload":{"score":null}}]},"as":"aql_script_seed_2"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_seed_2","key":["id"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"payload","to":"payload"}]}}]}],"edges":[]},"as":"aql_data_1"},{"from":"aql_data_1","match_nodes":{"definition":"N","where":{"gt":[{"property":{"name":"score","value":{"field":"payload"}}},{"literal":10}]},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","payload"],"label":"Person"},"as":"aql_keyed_seeds_3"},{"from":"aql_keyed_seeds_3","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Graph property predicate independent Program passes the ordinary checker" {
  match
    @check.check_parsed(
      graph_property_predicate_expected(),
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
test "Graph property predicate lowers to an independent complete Program" {
  let actual = match
    compile_query_script(
      @query.parse_query_script(
        graph_property_predicate_source("(a:Person WHERE a.payload.score > 10)"),
        syntax_limits(),
      ).unwrap(),
      graph_property_predicate_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(Expression(diagnostic)) => fail(@debug.to_string(diagnostic.issue))
    Err(_) => fail("unexpected lowering issue outside expression resolution")
  }
  assert_eq(semantic(actual), semantic(graph_property_predicate_expected()))
}

///|
test "Graph property predicate receivers retain qualified quoted and local scope" {
  for
    pattern in [
      "(a:Person WHERE payload.score > 10)", "(a:Person WHERE `A`.`PAYLOAD`.`score` > 10)",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(
        graph_property_predicate_source(pattern),
        syntax_limits(),
      ).unwrap(),
      graph_property_predicate_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(graph_property_predicate_expected()))
  }
}

///|
test "Graph property predicate supports an anonymous node without creating a variable" {
  let program = compile_query_script(
    @query.parse_query_script(
      graph_property_predicate_source(
        "(:Person WHERE payload.score > 10)",
        selection="id",
      ),
      syntax_limits(),
    ).unwrap(),
    graph_property_predicate_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(graph_property_predicate_expected()))
}

///|
test "Graph property predicate keeps scalar and property-map constraints connected" {
  for
    pattern in [
      "(a:Person WHERE a.id > 0)", "(a:Person {id: payload.score / 20})", "(a:Person WHERE payload.score IS NULL OR payload.score > 10)",
      "(a:Person WHERE COALESCE(payload.score, 0) = 0)",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(
        graph_property_predicate_source(pattern),
        syntax_limits(),
      ).unwrap(),
      graph_property_predicate_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        graph_rows_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      NeedsInputs(_) => fail("Values do not require acquisition")
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    }
  }
}

///|
test "Graph property predicate refuses foreign receivers and output aliases at lowering" {
  for
    predicate in ["missing.score > 0", "other.payload.score > 0", "chosen > 0"] {
    let result = compile_query_script(
      @query.parse_query_script(
        graph_property_predicate_source(
          "(a:Person WHERE " + predicate + ")",
          output="chosen",
        ),
        syntax_limits(),
      ).unwrap(),
      graph_property_predicate_context(),
      construction_limits(),
    )
    assert_true(
      result
      is Err(
        Expression({ issue: @expression.UnknownReference, origin: Some(_), })
      ),
      msg=predicate,
    )
  }
}

///|
test "Graph property predicate delegates missing members and scalar receivers to the checker" {
  for
    (predicate, missing) in [
      ("payload.missing > 0", true),
      ("id.score > 0", false),
    ] {
    let program = compile_query_script(
      @query.parse_query_script(
        graph_property_predicate_source("(a:Person WHERE " + predicate + ")"),
        syntax_limits(),
      ).unwrap(),
      graph_property_predicate_context(),
      construction_limits(),
    ).unwrap()
    guard @check.check_parsed(
        program,
        graph_rows_environment(),
        None,
        check_limits(),
      )
      is Rejected(diagnostic) else {
      fail("invalid object member/receiver must not pass ordinary checking")
    }
    guard @check.diagnostic_cause(diagnostic)
      is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
      fail("member failure belongs to ordinary pipeline typing")
    }
    if missing {
      assert_true(
        issue.kind is @pipeline.GraphMatch(Typing(UnknownField("missing"))),
      )
    } else {
      assert_true(
        issue.kind
        is @pipeline.GraphMatch(Typing(TypeMismatch("closed object receiver"))),
      )
    }
  }
}

///|
test "Graph property predicate retains expression work limits and source positions" {
  let result = compile_query_script(
    @query.parse_query_script(
      graph_property_predicate_source("(a:Person WHERE payload.score > 10)"),
      syntax_limits(),
    ).unwrap(),
    graph_property_predicate_context(),
    { ..construction_limits(), max_expression_work: 1, },
  )
  assert_true(result is Err(Expression({ issue: @expression.WorkLimit, .. })))
}
