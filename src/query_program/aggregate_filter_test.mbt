///|
test "aggregate WHERE preserves independent filters and ordinary demand" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","group":{"by":[],"aggregates":{"n":{"fn":"count","filter":{"literal":true}},"total":{"fn":"sum","expr":{"divide":[{"literal":1},{"literal":0}]},"filter":{"literal":false}}}}},{"select":["n","total"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n","total"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let generated = compile(
    @query.parse_query(
      "SELECT COUNT(* WHERE TRUE) AS n, SUM(1 / 0 WHERE FALSE) AS total",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
  match
    @check.check_parsed(generated, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "aggregate filters resolve the input scope and retain ordinary validation" {
  for
    text in [
      "SELECT COUNT(* WHERE amount > 0) AS n FROM orders", "SELECT COUNT(* WHERE o.amount > 0) AS n FROM orders AS o",
      "FROM orders |> AS before |> SET amount = 0 |> AGGREGATE COUNT(* WHERE before.amount > 0) AS n",
      "SELECT COUNT(* WHERE amount > 0) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n FROM orders",
    ] {
    let generated = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(generated, check_environment(), None, check_limits()) {
      Checked(_) | NeedsInputs(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
  for
    text in [
      "SELECT COUNT(* WHERE missing > 0) AS n FROM orders", "SELECT COUNT(*) AS n, SUM(amount WHERE n > 0) AS total FROM orders",
      "FROM orders |> AS old |> AS current |> AGGREGATE COUNT(* WHERE old.amount > 0) AS n",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
  let invalid = compile(
    @query.parse_query(
      "SELECT COUNT(* WHERE amount) AS n FROM orders",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(invalid, check_environment(), None, check_limits())
    is Rejected(_),
  )
}

///|
test "filtered DISTINCT array retains a non-argument predicate input" {
  // The admitted input supplies its id key; the frontend does not invent it.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","group":{"by":[],"aggregates":{"ids":{"fn":"array_agg","field":"id","distinct":true,"filter":{"gt":[{"field":"amount"},{"literal":0}]},"max_items":1000,"order_by":[{"field":"id","dir":"asc","nulls":"first"}]}}}},{"select":["ids"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["ids"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let generated = compile(
    @query.parse_query(
      "SELECT ARRAY_AGG(DISTINCT id IGNORE NULLS WHERE amount > 0 ORDER BY id) AS ids FROM orders",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
  for program in [expected, generated] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) | NeedsInputs(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
