///|
test "positive navigation offsets retain the independent literal and parameter Program" {
  // The expected Program was independently authored for the common analytic
  // contract. Unary plus must not add an expression or change either offset.
  for
    text in [
      "SELECT id, LAG(amount, +2) OVER (ORDER BY id) AS previous, LEAD(amount, +@p) OVER (ORDER BY id) AS next FROM orders ORDER BY id",
      "SELECT id, LAG(amount, +((+2))) OVER (ORDER BY id) AS previous, LEAD(amount, (+((+@P)))) OVER (ORDER BY id) AS next FROM orders ORDER BY id",
      "FROM orders |> SELECT id, LAG(amount, (+2)) OVER (ORDER BY id) AS previous, LEAD(amount, ++(@p)) OVER (ORDER BY id) AS next |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..values_context(),
        parameter_declarations: Some(number_parameter_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(grouped_analytic_offset_expected()))
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(grouped_analytic_offset_values("{\"p\":1}")),
        check_limits(),
      )
      is Checked(_),
    )
    for value in ["-1", "1.5", "null", "9007199254740992", "\"private\""] {
      assert_true(
        @check.check_parsed(
          actual,
          check_environment(),
          Some(grouped_analytic_offset_values("{\"p\":" + value + "}")),
          check_limits(),
        )
        is Rejected(_),
        msg=value,
      )
    }
  }
}

///|
test "positive navigation literals keep zero and exact integer bounds" {
  for value in ["+0", "(+(0))", "+9007199254740991"] {
    let actual = compile(
      @query.parse_query(
        "SELECT LAG(amount, " +
        value +
        ") OVER (ORDER BY id) AS previous FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "positive navigation syntax cannot disguise computation or invalid atoms" {
  for function in ["LAG", "LEAD"] {
    for
      value in [
        "+id", "+(id)", "+(1 + 1)", "+(@p + 1)", "+(-1)", "NULL", "(NULL)", "+NULL",
        "+((NULL))", "+(+(NULL))",
      ] {
      assert_true(
        compile(
          @query.parse_query(
            "SELECT " +
            function +
            "(amount, " +
            value +
            ") OVER (ORDER BY id) AS adjacent FROM orders",
            syntax_limits(),
          ).unwrap(),
          {
            ..values_context(),
            parameter_declarations: Some(number_parameter_declarations()),
          },
          construction_limits(),
        )
        is Err(InvalidQuery),
        msg=value,
      )
    }
    for value in ["+'2'", "+TRUE", "+1.5", "+9007199254740992", "+(-0)"] {
      assert_true(
        compile(
          @query.parse_query(
            "SELECT " +
            function +
            "(amount, " +
            value +
            ") OVER (ORDER BY id) AS adjacent FROM orders",
            syntax_limits(),
          ).unwrap(),
          values_context(),
          construction_limits(),
        )
        is Err(UnsupportedAnalytic),
        msg=value,
      )
    }
  }
}

///|
test "positive navigation traversal retains bounded work and original source origin" {
  let query = @query.parse_query(
    "SELECT LAG(amount, ++++++++++++2) OVER (ORDER BY id) AS previous FROM orders",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, values_context(), {
      ..construction_limits(),
      max_expression_work: 8,
    })
    is Err(Expression({ issue: WorkLimit, origin: Some(_), })),
  )
}
