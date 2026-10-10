///|
test "GROUP unary plus retains numeric admission and exposes its evaluated operand" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_group_key_0":{"negate":{"negate":{"field":"x"}}}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"x":"aql_group_key_0"},"n"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent numeric key Program must check")
  }
  for key in ["+x", "+(t.x)", "+((`t`.`X`))"] {
    let actual = match
      compile(
        @query.parse_query(
          "SELECT x, COUNT(*) AS n FROM t GROUP BY " + key + " ORDER BY x",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression({ issue: @expression.UnknownReference, .. })) =>
        fail("GROUP's admitted numeric identity key does not expose x")
      Err(_) => fail("unexpected refusal of the numeric identity key")
    }
    assert_eq(semantic(actual), semantic(expected), msg=key)
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the source key uses the ordinary numeric signature")
    }
  }
}

///|
test "GROUP unary plus retains nullable members and grouped scalar consumers" {
  for
    text in [
      "SELECT payload.score AS score, COUNT(*) AS n FROM objects GROUP BY +(objects.payload.score) ORDER BY score",
      "SELECT payload.score + 1 AS score, COUNT(*) AS n FROM objects GROUP BY +(objects.payload.score) HAVING score > 10 ORDER BY score",
      "SELECT COUNT(*) + payload.score AS n FROM objects GROUP BY +(objects.payload.score) ORDER BY n",
    ] {
    let program = checked_group_property(text)
    let body = semantic(program)
    assert_eq(body.split("\"property\":").length(), 2, msg=text)
    assert_eq(body.split("\"negate\":").length(), 3, msg=text)
  }
}

///|
test "GROUP unary plus does not restore other values or expired input ranges" {
  for
    text in [
      "SELECT y, COUNT(*) AS n FROM t GROUP BY +x", "SELECT x, COUNT(*) AS n FROM t GROUP BY -x",
      "SELECT x, COUNT(*) AS n FROM t GROUP BY +(x + 1)", "SELECT old.x, COUNT(*) AS n FROM t AS current GROUP BY +current.x",
      "SELECT x AS kept, COUNT(*) AS n FROM t GROUP BY +x |> SELECT t.x", "FROM t AS old |> AS current |> AGGREGATE COUNT(*) AS n GROUP BY +old.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
}

///|
test "GROUP unary plus keeps nonnumeric key rejection in the common checker" {
  for
    text in [
      "SELECT CAST(TRUE AS BOOL) AS flag, COUNT(*) AS n FROM t GROUP BY +CAST(TRUE AS BOOL)",
      "SELECT CAST('value' AS STRING) AS label, COUNT(*) AS n FROM t GROUP BY +CAST('value' AS STRING)",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program).split("\"negate\":").length(), 3)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Rejected(diagnostic) =>
        assert_eq(
          @check.diagnostic_category(diagnostic),
          @check.InvalidInput,
          msg=text,
        )
      _ => fail("the retained unary-plus key must reject a nonnumeric operand")
    }
  }
}

///|
test "GROUP unary plus preserves nested signs and one evaluated key" {
  let program = compile(
    @query.parse_query(
      "SELECT x, COUNT(*) AS n FROM t GROUP BY +(+x), t.x ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(program)
  assert_eq(body.split("\"negate\":").length(), 5)
  assert_true(body.contains("\"by\":[\"aql_group_key_0\"]"))
  assert_true(body.contains("\"select\":[{\"x\":\"aql_group_key_0\"},\"n\"]"))
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Checked(_),
  )
}
