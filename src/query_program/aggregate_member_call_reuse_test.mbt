///|
// Authored independently: the selected nullable member aggregate is evaluated
// once, and HAVING reads that result despite a different property AST spelling.
fn aggregate_member_call_reuse_expected(
  aggregate? : String = "{\"fn\":\"count\",\"expr\":{\"property\":{\"value\":{\"field\":\"payload\"},\"name\":\"score\"}}}",
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    ",{\"from\":\"objects\",\"group\":{\"by\":[],\"aggregates\":{\"n\":" +
    aggregate +
    (
      #|}}},{"filter":{"gt":[{"field":"n"},{"literal":0}]}},{"select":["n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "aggregate member reuse preserves equivalent per-call filters" {
  let expected = aggregate_member_call_reuse_expected(
    aggregate=(
      #|{"fn":"count","expr":{"property":{"name":"score","value":{"field":"payload"}}},"filter":{"gt":[{"property":{"name":"score","value":{"field":"payload"}}},{"literal":10}]}}
    ),
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    text in [
      "SELECT COUNT(payload.score WHERE payload.score > 10) AS n FROM objects HAVING COUNT((objects.payload).`SCORE` WHERE (payload).score > 10) > 0",
      "SELECT COUNT((payload).score WHERE (payload).score > 10) AS n FROM objects HAVING COUNT(payload.score WHERE objects.payload.`SCORE` > 10) > 0",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "aggregate member reuse keeps SELECT input and HAVING alias receivers separate" {
  for
    (receiver, count) in [
      ("(payload).score", 2),
      ("(objects.payload).score", 1),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT @assessment AS payload, COUNT(payload.score) AS n FROM objects HAVING COUNT(" +
        receiver +
        ") > 0",
        syntax_limits(),
      ).unwrap(),
      {
        ..aggregate_property_order_context(),
        parameter_declarations: Some(having_object_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(having_object_values()),
        check_limits(),
      )
      is Checked(_),
    )
    assert_eq(semantic(actual).split("\"fn\":\"count\"").length() - 1, count)
  }
}

///|
test "aggregate member reuse keeps explicit object and range receivers separate" {
  let actual = compile(
    @query.parse_query(
      "SELECT COUNT((payload).score) AS n FROM objects AS payload HAVING COUNT(payload.score) > 2",
      syntax_limits(),
    ).unwrap(),
    group_receiver_scope_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
  let body = semantic(actual)
  assert_eq(body.split("\"fn\":\"count\"").length() - 1, 2)
  assert_true(body.contains("\"field\":\"score\""))
  assert_true(body.contains("\"value\":{\"field\":\"payload\"}"))
}

///|
test "aggregate member reuse preserves DISTINCT filter and ordering differences" {
  for
    text in [
      "SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT(DISTINCT (payload).score) > 0",
      "SELECT COUNT(payload.score WHERE payload.score > 10) AS n FROM objects HAVING COUNT((payload).score WHERE payload.score > 20) > 0",
      "SELECT STRING_AGG(name, '|' ORDER BY payload.score, id) AS names FROM objects HAVING STRING_AGG(name, '|' ORDER BY (payload).score DESC, id) = 'c|a|b'",
      "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects HAVING STRING_AGG(name, '|' ORDER BY (payload).score NULLS FIRST, id) = 'c|b|a'",
    ] {
    let actual = checked_aggregate_property_order(text)
    assert_eq(semantic(actual).split("\"fn\":").length() - 1, 2, msg=text)
  }
}

///|
test "hidden aggregate member calls also share their evaluated result" {
  let actual = checked_aggregate_property_order(
    "SELECT COUNT(*) AS n FROM objects HAVING COUNT(payload.score) > 0 AND COUNT((objects.payload).`SCORE`) < 10",
  )
  assert_eq(semantic(actual).split("\"fn\":\"count\"").length() - 1, 2)
}

///|
test "independent selected member aggregate reuse Program checks normally" {
  assert_true(
    @check.check_parsed(
      aggregate_member_call_reuse_expected(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "HAVING reuses a selected aggregate across equivalent property receivers" {
  let expected = semantic(aggregate_member_call_reuse_expected())
  for
    text in [
      "SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT((payload).score) > 0",
      "SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT((objects.payload).`SCORE`) > 0",
      "SELECT COUNT((payload).score) AS n FROM objects HAVING COUNT(objects.payload.score) > 0",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      aggregate_property_order_context(),
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
test "aggregate member invalid receivers retain UnknownReference" {
  for
    text in [
      "SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT((missing).score) > 0",
      "SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT(n) > 0",
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
