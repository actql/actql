///|
fn computed_object_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":30}},{"id":1,"payload":{"score":20},"other":{"score":5}},{"id":3,"payload":null,"other":{"score":15}}]},"as":"objects"},{"from":"objects","derive":{"aql_query_expr_1":{"property":{"name":"score","value":{"coalesce":[{"field":"payload"},{"field":"other"}]}}}}},{"select":["id",{"score":"aql_query_expr_1"}]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn checked_computed_object(
  text : String,
  context? : Context = analytic_property_context(),
) -> @program.Program raise {
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("computed receiver uses the ordinary expression checker")
  }
  program
}

///|
test "computed object properties preserve grouping, CASE and implicit leaf names" {
  let expected = semantic(computed_object_expected())
  for
    text in [
      "SELECT id, (COALESCE(payload, other)).`score` FROM objects ORDER BY id", "SELECT id, COALESCE(payload, other).score FROM objects ORDER BY id",
    ] {
    assert_eq(semantic(checked_computed_object(text)), expected)
  }
  let wire = semantic(
    checked_computed_object(
      "FROM objects |> SELECT id, (CASE WHEN payload IS NULL THEN other ELSE payload END).score |> ORDER BY id",
    ),
  )
  assert_true(
    wire.contains("\"property\":{\"name\":\"score\",\"value\":{\"case\":"),
  )
}

///|
test "computed object properties guard ORDER reuse by receiver reference meaning" {
  let shared = semantic(
    checked_computed_object(
      "SELECT id, COALESCE(payload, other).score AS score FROM objects ORDER BY COALESCE(payload, other).score NULLS LAST, id",
    ),
  )
  assert_eq(shared.split("\"coalesce\":").length(), 2)
  let collision = semantic(
    checked_computed_object(
      "SELECT id, COALESCE(payload, other).score AS original_score, other AS payload FROM objects ORDER BY COALESCE(payload, other).score NULLS LAST, id",
    ),
  )
  assert_eq(collision.split("\"coalesce\":").length(), 3)
  let qualified = semantic(
    checked_computed_object(
      "SELECT id, COALESCE(payload, other).score AS original_score, other AS payload FROM objects ORDER BY COALESCE(objects.payload, objects.other).score NULLS LAST, id",
    ),
  )
  assert_eq(qualified.split("\"coalesce\":").length(), 3)
}

///|
test "computed object properties retain referenced JOIN inputs through the receiver" {
  let context = {
    ..analytic_property_context(),
    inputs: analytic_property_context().inputs + pair_context().inputs,
  }
  let wire = semantic(
    checked_computed_object(
      "SELECT COALESCE(o.payload, o.other).score AS score FROM objects AS o JOIN pair AS r ON o.id = r.x ORDER BY score",
      context~,
    ),
  )
  assert_true(wire.contains("\"join\":"))
  assert_true(
    wire.contains("\"property\":{\"name\":\"score\",\"value\":{\"coalesce\":"),
  )
}

///|
test "computed object properties retain the current Pipe scope and removed-range refusal" {
  let wire = semantic(
    checked_computed_object(
      "FROM objects AS original |> SET payload = other |> SELECT id, COALESCE(original.payload, original.other).score AS before, COALESCE(payload, other).score AS current |> ORDER BY id",
    ),
  )
  assert_true(wire.contains("\"field\":\"aql_pipe_set_3\""))
  assert_true(
    compile(
      @query.parse_query(
        "FROM objects AS old |> AS current |> SELECT COALESCE(old.payload, other).score AS score",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "computed object properties retain common member typing and expression work limits" {
  for receiver in ["COALESCE(payload, other).missing", "COALESCE(id, id).score"] {
    let program = compile(
      @query.parse_query(
        "SELECT " + receiver + " AS value FROM objects",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT COALESCE(payload, other).score AS score FROM objects",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: @expression.WorkLimit, .. })),
  )
}

///|
test "computed object properties match an independent checked Program" {
  let expected = computed_object_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail("computed object access is already an ordinary checked expression")
  }
  let program = compile(
    @query.parse_query(
      "SELECT id, COALESCE(payload, other).score AS score FROM objects ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    analytic_property_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}
