///|
test "aggregate membership order preserves an independently checked complete Program" {
  let key = "{\"in\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":[20,null]}]}"
  let expected = aggregate_signed_order_key_expected(key, "")
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the ordinary membership control must be closed")
  }
  let actual = match
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY payload.score IN (20, NULL) NULLS LAST, id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedAggregate) =>
      fail("common membership ordering is not connected")
    Err(_) => fail("unexpected membership order refusal")
  }
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "aggregate membership interval and null-safe keys retain independent expressions" {
  for
    (key, expected) in [
      (
        "payload.score IN (20, NULL)", "{\"in\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":[20,null]}]}",
      ),
      (
        "payload.score NOT IN (20)", "{\"not_in\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":[20]}]}",
      ),
      (
        "((objects.payload)).`SCORE` IN UNNEST([20, NULL])", "{\"in\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":[20,null]}]}",
      ),
      (
        "payload.score NOT IN UNNEST(ARRAY[20])", "{\"not_in\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":[20]}]}",
      ),
      (
        "payload.score BETWEEN 5 AND 15", "{\"between\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":5},{\"literal\":15}]}",
      ),
      (
        "payload.score NOT BETWEEN 5 AND 15", "{\"not\":{\"between\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":5},{\"literal\":15}]}}",
      ),
      (
        "payload.score IS DISTINCT FROM 20", "{\"is_distinct_from\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":20}]}",
      ),
      (
        "payload.score IS NOT DISTINCT FROM NULL", "{\"not\":{\"is_distinct_from\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":null}]}}",
      ),
    ] {
    let control = aggregate_signed_order_key_expected(expected, "")
    match
      @check.check_parsed(control, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(_) => fail("independent predicate control rejected: " + key)
      _ => fail("independent predicate control must be closed")
    }
    for
      text in [
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        key +
        " NULLS LAST, id) AS names FROM objects",
        "FROM objects |> AGGREGATE STRING_AGG(name, '|' ORDER BY " +
        key +
        " NULLS LAST, id) AS names",
      ] {
      assert_eq(
        semantic(checked_aggregate_property_order(text)),
        semantic(control),
        msg=text,
      )
    }
  }
}

///|
test "aggregate predicate operands keep demand and DISTINCT refusals" {
  for
    key in [
      "(id / 0) IN (1)", "payload.score BETWEEN 0 AND id / 0", "payload.score IS DISTINCT FROM CAST(name AS FLOAT64)",
      "id IN UNNEST([id / 0])", "id IN UNNEST(IF(FALSE, [id / 0], [id]))", "name LIKE 'a%'",
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
        "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY payload.score IN (20, NULL), id) AS names FROM objects",
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
        "FROM objects AS old |> AS `current` |> AGGREGATE STRING_AGG(name, '|' ORDER BY old.payload.score IN (20), id) AS names",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "aggregate predicates retain common operand and membership-list admission" {
  for
    key in [
      "payload.score IN ('wrong')", "payload.missing BETWEEN 1 AND 2", "payload.score IS DISTINCT FROM TRUE",
      "payload.score IN UNNEST([TRUE])",
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
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
      msg=key,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY payload.score IN (id), id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.InvalidArguments, .. })),
  )
}

///|
test "aggregate membership retains unsupported annotated and computed list contracts" {
  for
    key in [
      "payload.score IN UNNEST(ARRAY<FLOAT64>[20])", "payload.score IN UNNEST([id])",
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
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Rejected(error) =>
        assert_true(@check.diagnostic_cause(error) is Source(_), msg=key)
      _ =>
        fail(
          "general membership lists remain unsupported by common admission: " +
          key,
        )
    }
  }
}

///|
test "aggregate membership keeps typed parameter values and missing declaration refusal" {
  let declarations = "{\"wanted\":{\"type\":\"number\",\"nullable\":true}}"
  let actual = compile(
    @query.parse_query(
      "FROM objects |> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score IN (@WANTED, NULL) NULLS LAST, id) AS names",
      syntax_limits(),
    ).unwrap(),
    {
      ..aggregate_property_order_context(),
      parameter_declarations: Some(
        parameter_reference_declarations(declarations),
      ),
    },
    construction_limits(),
  ).unwrap()
  let control = aggregate_signed_order_key_expected(
    "{\"in\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":[{\"$param\":\"wanted\"},null]}]}",
    "\"params\":" + declarations + ",",
  )
  assert_eq(semantic(actual), semantic(control))
  for values in ["{\"wanted\":20}", "{\"wanted\":null}"] {
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(aggregate_order_parameter_values(values)),
        check_limits(),
      )
      is Checked(_),
    )
  }
  let undeclared = compile(
    @query.parse_query(
      "SELECT STRING_AGG(name, '|' ORDER BY payload.score IN (@missing), id) AS names FROM objects",
      syntax_limits(),
    ).unwrap(),
    aggregate_property_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(undeclared, check_environment(), None, check_limits())
    is Rejected(_),
  )
}
