///|
test "HAVING hidden property ORDER has an independent checked Program" {
  // The hidden STRING_AGG must sort the input object's score before filtering.
  // The independent ordinary Group/derive Program is admitted first.
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","derive":{"aql_aggregate_sort_5":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":[],"aggregates":{"n":{"fn":"count"},"aql_having_aggregate_0":{"fn":"string_agg","field":"name","max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_5","dir":"asc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"delimiter":"|"}}}},{"filter":{"eq":[{"field":"aql_having_aggregate_0"},{"literal":"b|a|c"}]}},{"select":["n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(cause) => raise cause
        cause => raise cause
      }
    _ => fail("the independent Group/derive control has closed Values input")
  }
  let actual = compile(
    @query.parse_query(
      "SELECT COUNT(*) AS n FROM objects HAVING STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) = 'b|a|c'",
      syntax_limits(),
    ).unwrap(),
    aggregate_property_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "HAVING property order never reuses a SELECT input receiver for its alias" {
  let context = {
    ..aggregate_property_order_context(),
    parameter_declarations: Some(having_object_declarations()),
  }
  for
    (order, properties, aggregates) in [
      ("payload.score", 2, 2),
      ("objects.payload.score", 1, 1),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT @assessment AS payload, STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS original FROM objects HAVING STRING_AGG(name, '|' ORDER BY " +
        order +
        " NULLS LAST, id) = 'a|b|c'",
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(having_object_values()),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) =>
        match @check.diagnostic_cause(error) {
          Source(cause) => raise cause
          cause => raise cause
        }
      _ => fail("typed alias properties use ordinary Group/expression checking")
    }
    let body = semantic(actual)
    assert_eq(body.split("\"property\":").length() - 1, properties)
    assert_eq(body.split("\"fn\":").length() - 1, aggregates)
    assert_true(body.contains("\"value\":{\"field\":\"payload\"}"))
    if properties == 2 {
      assert_true(body.contains("\"value\":{\"field\":\"aql_having_argument_"))
    }
  }
}
