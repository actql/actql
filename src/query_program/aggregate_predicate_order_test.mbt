///|
test "aggregate predicate order retains an independently checked complete Program" {
  let expected = aggregate_signed_order_key_expected(
    "{\"is_null\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}}",
    "",
  )
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Boolean order Program must be closed")
  }
  let actual = match
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY payload.score IS NULL NULLS LAST, id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedAggregate) =>
      fail("supported Boolean order rejected by the Frontend")
    Err(_) => fail("unexpected predicate-order lowering refusal")
  }
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "aggregate Boolean keys preserve independent comparisons and three-valued logic" {
  for
    (key, expected) in [
      (
        "payload.score > 15", "{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":15}]}",
      ),
      (
        "NOT (payload.score > 15)", "{\"not\":{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":15}]}}",
      ),
      (
        "(payload.score > 15) OR id = 3", "{\"or\":[{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":15}]},{\"eq\":[{\"field\":\"id\"},{\"literal\":3}]}]}",
      ),
      (
        "(payload.score > 15) IS UNKNOWN", "{\"is_unknown\":{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":15}]}}",
      ),
    ] {
    let control = aggregate_signed_order_key_expected(expected, "")
    assert_true(
      @check.check_parsed(control, check_environment(), None, check_limits())
      is Checked(_),
      msg=key,
    )
    for
      text in [
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        key +
        " NULLS LAST, id) AS names FROM objects",
        "FROM objects |> AGGREGATE STRING_AGG(name, '|' ORDER BY " +
        key +
        " NULLS LAST, id) AS names",
      ] {
      let actual = checked_aggregate_property_order(text)
      assert_eq(semantic(actual), semantic(control), msg=text)
    }
  }
}

///|
test "aggregate Boolean keys preserve scope and per-call filters" {
  let actual = checked_aggregate_property_order(
    "FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((t.payload)).`SCORE` IS NULL NULLS LAST, id) AS names",
  )
  assert_eq(
    semantic(actual),
    semantic(
      aggregate_signed_order_key_expected(
        "{\"is_null\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}}",
        "",
      ),
    ),
  )
  let masked = checked_aggregate_property_order(
    "SELECT STRING_AGG(IF(id / (id - id) = 0, name, name), '|' WHERE FALSE ORDER BY payload.score IS NULL, id) AS names FROM objects",
  )
  assert_true(semantic(masked).contains("\"filter\":{\"literal\":false}"))
  assert_eq(semantic(masked).split("\"derive\":").length(), 2)
}

///|
test "aggregate Boolean keys keep demanded failures and DISTINCT restrictions" {
  for
    key in [
      "id / 0 > 1", "(id + 1) IS NULL", "NOT (CAST(name AS FLOAT64) > 0)", "IF(FALSE, id / 0, id) = 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT STRING_AGG(name, '|' WHERE FALSE ORDER BY " +
          key +
          ", id) AS names FROM objects",
          syntax_limits(),
        ).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=key,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY payload.score IS NULL, id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedAggregate),
  )
  assert_true(
    compile(
      @query.parse_query(
        "FROM objects AS old |> AS current |> AGGREGATE STRING_AGG(name, '|' ORDER BY old.payload.score IS NULL, id) AS names",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
  for key in ["id AND TRUE", "payload.missing IS NULL"] {
    let actual = compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        key +
        ", id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
      msg=key,
    )
  }
}
