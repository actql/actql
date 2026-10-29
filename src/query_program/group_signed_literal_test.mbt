///|
// Independent complete Program: the input key contains one admitted number,
// and SELECT reads the evaluated key rather than the removed input column.
fn signed_literal_group_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"next":"aql_group_key_0"},"n"]},{"sort":[{"field":"next","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["next","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "GROUP signed literals reuse their independently admitted numeric value" {
  let expected = signed_literal_group_expected()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (selected, grouped) in [
      ("+1", "1"),
      ("1", "+1"),
      ("+(1.0)", "1e0"),
      ("-(-1)", "1"),
      ("+(-(-1))", "+1.00"),
    ] {
    let text = "SELECT x + " +
      selected +
      " AS next, COUNT(*) AS n FROM t GROUP BY x + " +
      grouped +
      " ORDER BY next"
    let actual = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression({ issue: @expression.UnknownReference, .. })) =>
        fail(text + ": UnknownReference")
      Err(_) => fail(text + ": another lowering failure")
    }
    assert_eq(semantic(actual), semantic(expected), msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "signed literal DISTINCT ORDER reads the independent evaluated output" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_query_expr_0":{"add":[{"field":"x"},{"literal":1}]}}},{"select":[{"next":"aql_query_expr_0"}]},{"distinct":["next"]},{"sort":[{"field":"next","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["next"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT DISTINCT x + +1 AS next FROM t ORDER BY t.x + 1", "SELECT DISTINCT x + 1 AS next FROM t ORDER BY t.x + +(1.0)",
      "FROM t |> SELECT DISTINCT x + +1 AS next |> ORDER BY t.x + 1",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "signed literal comparison never equates different values or invalid atoms" {
  // Expression tokens normalize signed zero; JSON value admission stays strict.
  let zero = compile(
    @query.parse_query(
      "SELECT x + 0 AS next, COUNT(*) AS n FROM t GROUP BY x + 0",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  for atom in ["-0", "-(-0)"] {
    let actual = compile(
      @query.parse_query(
        "SELECT x + " + atom + " AS next, COUNT(*) AS n FROM t GROUP BY x + 0",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(zero), msg=atom)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }

  assert_true(
    compile(
      @query.parse_query(
        "SELECT x + +2 AS next, COUNT(*) AS n FROM t GROUP BY x + 1",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
  for atom in ["+9007199254740992"] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT x + " +
          atom +
          " AS next, COUNT(*) AS n FROM t GROUP BY x + " +
          atom,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.InvalidNumber, .. })),
      msg=atom,
    )
  }
}

///|
test "signed literal reuse preserves ORDER alias receiver meaning" {
  let body = checked_join_order(
    "SELECT DISTINCT -x + +1 AS x FROM t ORDER BY -x + 1",
  )
  assert_eq(body.split("\"add\":").length() - 1, 2)
  assert_true(body.contains("\"field\":\"x\""))
  assert_true(body.contains("aql_pipe_sort_"))
  assert_true(body.contains("\"fields\":[\"x\"]"))
}
