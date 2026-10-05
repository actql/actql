///|
fn order_property_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":30}},{"id":1,"payload":{"score":20},"other":{"score":5}},{"id":3,"payload":null,"other":{"score":15}}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["id", "payload", "other"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "SQL ORDER property paths only reuse matching receiver slots" {
  for suffix in ["payload.score", "payload.score + 1", "`payload`.`score`"] {
    let program = compile(
      @query.parse_query(
        "SELECT id, " +
        suffix +
        " AS original_score, other AS payload FROM objects ORDER BY " +
        suffix +
        " NULLS LAST",
        syntax_limits(),
      ).unwrap(),
      order_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(program).contains(
        "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"other\"}}",
      ),
      msg="ORDER reads the evaluated output receiver, not SELECT's input receiver",
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("receiver rebinding uses ordinary checking")
    }
  }
}

///|
test "SQL ORDER property paths use the common nullable object expression" {
  for
    text in [
      "SELECT id FROM objects ORDER BY payload.score + 1 NULLS LAST", "SELECT id FROM objects ORDER BY objects.payload.score NULLS LAST",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      order_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"property\""))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("closed Values need no external inputs")
    }
  }
}

///|
test "SQL ORDER property paths resolve evaluated output aliases before input" {
  for
    (text, field) in [
      (
        "SELECT id, other AS payload FROM objects ORDER BY payload.score", "other",
      ),
      (
        "SELECT id, other AS payload FROM objects ORDER BY objects.payload.score NULLS LAST",
        "payload",
      ),
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      order_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(program).contains(
        "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"" +
        field +
        "\"}}",
      ),
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("closed output aliases retain ordinary checking")
    }
  }
}

///|
test "SQL ORDER property paths match an independent complete Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT id FROM objects ORDER BY payload.score NULLS LAST",
      syntax_limits(),
    ).unwrap(),
    order_property_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":30}},{"id":1,"payload":{"score":20},"other":{"score":5}},{"id":3,"payload":null,"other":{"score":15}}]},"as":"objects"},{"from":"objects","derive":{"aql_query_sort_4":{"property":{"value":{"field":"payload"},"name":"score"}}}},{"sort":[{"field":"aql_query_sort_4","dir":"asc","nulls":"last"}]},{"select":["id"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for program in [actual, expected] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("independent and generated Programs use ordinary checking")
    }
  }
}

///|
test "SQL ORDER property paths preserve output scope and common type checks" {
  match
    compile(
      @query.parse_query(
        "SELECT DISTINCT id FROM objects ORDER BY payload.score",
        syntax_limits(),
      ).unwrap(),
      order_property_context(),
      construction_limits(),
    ) {
    Err(UnsupportedOrdering) => ()
    _ => fail("DISTINCT removed the input object")
  }
  for
    text in [
      "SELECT id FROM objects ORDER BY payload.missing", "SELECT id FROM objects ORDER BY id.score",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      order_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg="the common checker owns missing fields and non-object receivers",
    )
  }
}

///|
test "SQL ORDER property paths retain DATA parameter declarations and values" {
  let declaration_source = @wire.admit(
    @source.parse_json(
      (
        #|{"a":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"b":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let declarations = @parameters.read_declarations(Some(declaration_source), {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let values = @wire.admit(
    @source.parse_json(
      (
        #|{"a":{"score":10},"b":null}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let script = @query.parse_query_script(
    "DATA objects = SELECT 2 AS id, @a AS payload UNION ALL SELECT 1 AS id, @b AS payload; SELECT id FROM objects ORDER BY payload.score NULLS LAST",
    syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(declarations),
    },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      program,
      check_environment(),
      Some(values),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("declared object parameters are bound without an acquisition")
  }
}
