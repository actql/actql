///|
fn aggregate_conditional_order_key() -> String {
  "{\"coalesce\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":0}]}"
}

///|
test "conditional aggregate order has an independently checked ordinary Program" {
  assert_true(
    @check.check_parsed(
      aggregate_signed_order_key_expected(aggregate_conditional_order_key(), ""),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "conditional aggregate order source retains the independent complete Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names FROM objects",
      syntax_limits(),
    ).unwrap(),
    aggregate_property_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(
    semantic(actual),
    semantic(
      aggregate_signed_order_key_expected(aggregate_conditional_order_key(), ""),
    ),
  )
}

///|
test "conditional aggregate order preserves ordinary IF CASE and computed receiver trees" {
  for
    (key, expected) in [
      (
        "`IFNULL`((objects.payload).score, 0)",
        aggregate_conditional_order_key(),
      ),
      (
        "IF(payload.score IS NULL, 0, -payload.score)", "{\"if\":[{\"is_null\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}},{\"literal\":0},{\"negate\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}}]}",
      ),
      (
        "CASE WHEN id = 1 THEN 0 ELSE payload.score END", "{\"case\":{\"when\":[{\"when\":{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]},\"then\":{\"literal\":0}}],\"else\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}}}",
      ),
      (
        "COALESCE(payload, other).score", "{\"property\":{\"name\":\"score\",\"value\":{\"coalesce\":[{\"field\":\"payload\"},{\"field\":\"other\"}]}}}",
      ),
    ] {
    let actual = checked_aggregate_property_order(
      "SELECT STRING_AGG(name, '|' ORDER BY " +
      key +
      " NULLS LAST, id) AS names FROM objects",
    )
    assert_eq(
      semantic(actual),
      semantic(aggregate_signed_order_key_expected(expected, "")),
    )
  }
}

///|
test "conditional order leaves signatures properties and operand types to the checker" {
  for
    key in [
      "IFNULL(payload.score, 'bad')", "IF(id, 0, payload.score)", "COALESCE(payload, other).missing",
      "IFNULL(id)",
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        key +
        ", id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    match actual {
      Ok(program) =>
        assert_true(
          @check.check_parsed(
            program,
            check_environment(),
            None,
            check_limits(),
          )
          is Rejected(_),
          msg=key,
        )
      Err(Expression(_)) => ()
      _ =>
        fail(
          "conditional order must retain the existing expression/checker refusal",
        )
    }
  }
}

///|
test "conditional order cannot expose removed ranges or hoist potentially failing operands" {
  for
    key in [
      "COALESCE(id / (id - id), 0)", "IF(FALSE, id / 0, id)", "CASE WHEN FALSE THEN CAST(name AS FLOAT64) ELSE id END",
      "COALESCE(SQRT(id), 0)",
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
        "FROM objects AS old |> AS current |> AGGREGATE STRING_AGG(name, '|' ORDER BY COALESCE(old.payload.score, 0), id) AS names",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(Expression(_)),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY COALESCE(payload.score, 0)) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedAggregate),
  )
}
