///|
fn analytic_string_agg_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"names":{"fn":"string_agg","field":"name","max_bytes":10000,"delimiter":"|"}},"frame":{"start":"unbounded_preceding","end":"current_row"}}},{"select":["id","names"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","names"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "analytic STRING_AGG independent complete Program passes common checker" {
  match
    @check.check_parsed(
      analytic_string_agg_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Values control is closed")
  }
}

///|
test "SQL and Pipe analytic STRING_AGG match the independent Program" {
  let call = "STRING_AGG(name, '|') OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS names"
  let grouped = "STRING_AGG(name, (('|'))) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS names"
  for
    text in [
      "SELECT id, " + call + " FROM objects ORDER BY id",
      "FROM objects |> SELECT id, " + call + " |> ORDER BY id",
      "SELECT id, " + grouped + " FROM objects ORDER BY id",
      "FROM objects |> SELECT id, " + grouped + " |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(analytic_string_agg_expected()))
  }
}

///|
test "analytic STRING_AGG preserves the caller's collection byte ceiling" {
  let query = @query.parse_query(
    "SELECT STRING_AGG(name) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS names FROM objects",
    syntax_limits(),
  ).unwrap()
  let actual = compile(query, aggregate_property_order_context(), {
    ..construction_limits(),
    max_collection_bytes: 17L,
  }).unwrap()
  let wire = semantic(actual)
  assert_true(wire.contains("\"max_bytes\":17"))
  assert_true(wire.contains("\"delimiter\":\",\""))
  assert_false(wire.contains("\"order_by\":[]"))
  for bound in [0L, -1L, 9007199254740992L] {
    assert_true(
      compile(query, aggregate_property_order_context(), {
        ..construction_limits(),
        max_collection_bytes: bound,
      })
      is Err(UnsupportedAggregate),
    )
  }
}

///|
test "analytic STRING_AGG refuses aggregate modifiers and missing frames" {
  for
    text in [
      "SELECT STRING_AGG(DISTINCT name, '|') OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS names FROM objects",
      "SELECT STRING_AGG(name WHERE id > 0) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS names FROM objects",
      "SELECT STRING_AGG(name ORDER BY id) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS names FROM objects",
      "SELECT STRING_AGG(name) OVER (ORDER BY id) AS names FROM objects",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
      msg=text,
    )
  }
}

///|
test "analytic STRING_AGG keeps its SELECT input scope" {
  for
    text in [
      "SELECT name AS invented, STRING_AGG(invented) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS names FROM objects",
      "FROM objects AS old |> AS current |> SELECT STRING_AGG(old.name) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS names",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
}
