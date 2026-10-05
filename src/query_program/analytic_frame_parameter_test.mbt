///|
fn analytic_frame_parameter_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","params":{"p":{"type":"number"}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"first":{"fn":"first_value","expr":{"field":"amount"}},"last":{"fn":"last_value","expr":{"field":"amount"}}},"frame":{"start":{"preceding":{"$param":"p"}},"end":{"following":{"$param":"p"}}}}},{"select":["id","first","last"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","first","last"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn analytic_frame_parameter_values(value : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(
      "{\"p\":" + value + "}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "independent frame Parameter Program retains common numeric validation" {
  let expected = analytic_frame_parameter_expected()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    )
    is Checked(_),
  )
  for value in ["0", "-1", "1.5", "null", "9007199254740992", "\"private\""] {
    assert_true(
      @check.check_parsed(
        expected,
        check_environment(),
        Some(analytic_frame_parameter_values(value)),
        check_limits(),
      )
      is Rejected(_),
    )
  }
}

///|
test "SQL and Pipe frame Parameters match the independent complete Program" {
  let frame = "ORDER BY id ROWS BETWEEN @p PRECEDING AND @p FOLLOWING"
  for
    text in [
      "SELECT id, FIRST_VALUE(amount) OVER (" +
      frame +
      ") AS first, LAST_VALUE(amount) OVER (" +
      frame +
      ") AS last FROM orders ORDER BY id",
      "FROM orders |> SELECT id, FIRST_VALUE(amount) OVER (" +
      frame +
      ") AS first, LAST_VALUE(amount) OVER (" +
      frame +
      ") AS last |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..values_context(),
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(analytic_frame_parameter_expected()))
  }
}

///|
test "reversed bound frame Parameters retain the common frame rejection" {
  for (direction, value) in [("PRECEDING", "1"), ("FOLLOWING", "3")] {
    let actual = compile(
      @query.parse_query(
        "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN @p " +
        direction +
        " AND 2 " +
        direction +
        ") AS first FROM orders",
        syntax_limits(),
      ).unwrap(),
      {
        ..values_context(),
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(analytic_frame_parameter_values(value)),
        check_limits(),
      ) {
      Rejected(diagnostic) => {
        assert_true(
          @check.diagnostic_cause(diagnostic)
          is Closure(Operations(Frames(InvalidFrame(_)))),
        )
        // Record the common classification without pinning the defective one.
        println(
          if @check.diagnostic_category(diagnostic) is UnclassifiedFailure {
            "UnclassifiedFailure"
          } else {
            "Classified frame rejection"
          },
        )
      }
      _ => fail("Reversed bound intervals must remain rejected")
    }
  }
}
