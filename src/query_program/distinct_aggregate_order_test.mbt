///|
test "DISTINCT aggregate ordering refuses a different argument source" {
  for
    text in [
      "SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY y) AS items FROM pair",
      "FROM pair |> AGGREGATE ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY y) AS items",
      "SELECT ARRAY_AGG(DISTINCT p.x IGNORE NULLS ORDER BY p.y) AS items FROM pair AS p",
      "SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY x, y) AS items FROM pair",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=text,
    )
  }
}

///|
fn distinct_order_string_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","group":{"by":[],"aggregates":{"names":{"fn":"string_agg","field":"name","distinct":true,"max_bytes":10000,"order_by":[{"field":"name","dir":"asc","nulls":"first"}],"delimiter":"|"}}}},{"select":["names"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["names"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "DISTINCT order preserves one resolved argument across qualification" {
  let expected = distinct_order_string_expected()
  for
    text in [
      "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY name) AS names FROM objects",
      "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY objects.name) AS names FROM objects",
      "SELECT STRING_AGG(DISTINCT o.name, '|' ORDER BY (`o`.`NAME`)) AS names FROM objects AS o",
      "FROM objects AS old |> SET name = 'changed' |> AGGREGATE STRING_AGG(DISTINCT old.name, '|' ORDER BY old.name) AS names",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    if !text.contains("SET") {
      assert_eq(semantic(actual), semantic(expected))
    }
    for program in [expected, actual] {
      assert_true(
        @check.check_parsed(program, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}

///|
test "DISTINCT order checks computed and property receiver identity" {
  for
    text in [
      "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY id) AS names FROM objects",
      "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY name, id) AS names FROM objects",
      "SELECT ARRAY_AGG(DISTINCT payload.score IGNORE NULLS ORDER BY other.score) AS items FROM objects",
      "FROM objects AS before |> SET name = 'changed' |> AGGREGATE STRING_AGG(DISTINCT name, '|' ORDER BY before.name) AS names",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=text,
    )
  }
  for
    text in [
      "SELECT ARRAY_AGG(DISTINCT payload.score IGNORE NULLS ORDER BY objects.payload.score) AS items FROM objects",
      "SELECT ARRAY_AGG(DISTINCT objects.payload.score IGNORE NULLS ORDER BY payload.`SCORE`) AS items FROM objects",
      "SELECT ARRAY_AGG(DISTINCT (payload).score IGNORE NULLS ORDER BY objects.payload.score) AS items FROM objects",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Ok(_),
      msg=text,
    )
  }
}
