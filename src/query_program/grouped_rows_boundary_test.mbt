///|
test "wrapped ROWS Parameters match the complete independent analytic Program" {
  let expected = analytic_frame_parameter_expected()
  for
    frame in [
      "ORDER BY id ROWS BETWEEN (+@p) PRECEDING AND ((@p)) FOLLOWING", "ORDER BY id ROWS BETWEEN ++((@p)) PRECEDING AND +(@p) FOLLOWING",
    ] {
    let projection = "id, FIRST_VALUE(amount) OVER (" +
      frame +
      ") AS first, LAST_VALUE(amount) OVER (" +
      frame +
      ") AS last"
    for
      text in [
        "SELECT " + projection + " FROM orders ORDER BY id",
        "FROM orders |> SELECT " + projection + " |> ORDER BY id",
      ] {
      let actual = compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        {
          ..values_context(),
          parameter_declarations: Some(number_parameter_declarations()),
        },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      assert_true(
        @check.check_parsed(
          actual,
          check_environment(),
          Some(analytic_frame_parameter_values("1")),
          check_limits(),
        )
        is Checked(_),
      )
      for value in ["0", "-1", "1.5", "null"] {
        assert_true(
          @check.check_parsed(
            actual,
            check_environment(),
            Some(analytic_frame_parameter_values(value)),
            check_limits(),
          )
          is Rejected(_),
          msg=value,
        )
      }
    }
  }
}

///|
test "wrapped zero ROWS retains legal current row projection and forbidden categories" {
  let expected = zero_rows_frame_expected(
    "{\"start\":\"current_row\",\"end\":\"current_row\"}",
  )
  for
    boundary in ["(+0) PRECEDING", "BETWEEN (+0) PRECEDING AND ((0)) FOLLOWING"] {
    for
      text in [
        "SELECT id, SUM(amount) OVER (ORDER BY id ROWS " +
        boundary +
        ") AS total FROM flags ORDER BY id",
        "FROM flags |> SELECT id, SUM(amount) OVER (ORDER BY id ROWS " +
        boundary +
        ") AS total |> ORDER BY id",
      ] {
      let actual = compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        analytic_countif_context(),
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      assert_true(
        @check.check_parsed(
          actual,
          check_environment(numeric=true),
          None,
          check_limits(),
        )
        is Checked(_),
      )
    }
  }
  for
    boundary in [
      "(+0) FOLLOWING", "BETWEEN CURRENT ROW AND (+0) PRECEDING", "BETWEEN (+0) FOLLOWING AND CURRENT ROW",
    ] {
    let text = "SELECT SUM(amount) OVER (ORDER BY id ROWS " +
      boundary +
      ") AS total FROM flags"
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        analytic_countif_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=boundary,
    )
  }
}
