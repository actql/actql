///|
fn distinct_array_reference_seed() -> String {
  (
    #|{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":2,"y":100},{"x":1,"y":200},{"x":2,"y":300}]},"as":"pair"}
  )
}

///|
fn distinct_array_reference_context() -> Context {
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "pair", quoted: false, }],
        name: "pair",
        source: GeneratedValues(
          unnest_value_cursor(distinct_array_reference_seed()),
        ),
        visible_fields: ["x", "y"],
        graph_bindings: [],
      },
    ],
  }
}

///|
// The common DISTINCT owner derives the real candidate key from the projected
// value, independent of unrelated y. No authored uniqueness is assumed.
fn distinct_array_reference_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    distinct_array_reference_seed() +
    (
      #|,{"from":"pair","select":["x"]},{"distinct":["x"]},{"group":{"by":[],"aggregates":{"items":{"fn":"array_agg","field":"x","distinct":true,"max_items":1000,"order_by":[{"field":"x","dir":"desc","nulls":"last"}]}}}},{"select":["items"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["items"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent DISTINCT ARRAY key Program checks without invented evidence" {
  assert_true(
    @check.check_parsed(
      distinct_array_reference_expected(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "equivalent aggregate argument and order references retain the DISTINCT key Program" {
  let expected = semantic(distinct_array_reference_expected())
  for
    text in [
      "SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY x DESC) AS items FROM pair",
      "SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY p.x DESC) AS items FROM pair AS p",
      "SELECT ARRAY_AGG(DISTINCT p.x IGNORE NULLS ORDER BY x DESC) AS items FROM pair AS p",
      "SELECT ARRAY_AGG(DISTINCT ((x)) IGNORE NULLS ORDER BY (`p`.`X`) DESC) AS items FROM pair AS p",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      distinct_array_reference_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), expected, msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=text,
    )
  }
}

///|
test "DISTINCT ARRAY key reuse cannot substitute another order input" {
  for
    text in [
      "SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY p.y) AS items FROM pair AS p",
      "SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY -p.x) AS items FROM pair AS p",
      "SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY x, y) AS items FROM pair",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        distinct_array_reference_context(),
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=text,
    )
  }
}

///|
test "DISTINCT ARRAY property orders keep ordinary common admission" {
  for
    text in [
      "SELECT ARRAY_AGG(DISTINCT payload.score IGNORE NULLS ORDER BY payload.score) AS items FROM objects",
      "SELECT ARRAY_AGG(DISTINCT ((payload).score) IGNORE NULLS ORDER BY objects.payload.`SCORE`) AS items FROM objects",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Rejected(error) =>
        match @check.diagnostic_cause(error) {
          Source(SourceView(Program(Program(Pipeline(_, issue)))))
          | Source(SourceView(Program(Program(Order(_, PipelineOrder(issue)))))) =>
            assert_true(issue.kind is UnresolvedOrder, msg=text)
          cause => raise cause
        }
      _ => fail("expected existing property admission refusal")
    }
    // Nullable property/order evidence is not fabricated by the shortcut.
    assert_true(!semantic(program).contains("\"distinct\":["), msg=text)
  }
}
