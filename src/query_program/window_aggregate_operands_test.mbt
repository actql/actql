///|
fn window_aggregate_operand_expected(
  aggregate : String,
  function_body : String,
  frame : String,
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    qualify_group_collision_seed() +
    ",{\"from\":\"t\",\"group\":{\"by\":[\"x\"],\"aggregates\":{\"aql_select_aggregate_0\":" +
    aggregate +
    "}}},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"field\":\"x\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"functions\":{\"value\":" +
    function_body +
    "}" +
    frame +
    "}},{\"select\":[\"x\",\"value\"]},{\"sort\":[{\"field\":\"x\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"x\",\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn check_window_operand_control(expected : @program.Program) -> Unit raise {
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent grouped window operand Program must check")
  }
}

///|
test "independent grouped navigation and running sum operand Programs check" {
  check_window_operand_control(
    window_aggregate_operand_expected(
      "{\"fn\":\"count\"}", "{\"fn\":\"lag\",\"expr\":{\"field\":\"aql_select_aggregate_0\"}}",
      "",
    ),
  )
  check_window_operand_control(
    window_aggregate_operand_expected(
      "{\"fn\":\"sum\",\"field\":\"y\"}", "{\"fn\":\"sum\",\"field\":\"aql_select_aggregate_0\"}",
      ",\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"}",
    ),
  )
}

///|
test "navigation consumes evaluated ordinary COUNT rather than a scalar function" {
  // Counts are 2 and 1 in ascending x order; previous is NULL then 2.
  let actual = compile(
    @query.parse_query(
      "SELECT t.x, LAG(COUNT(*)) OVER (ORDER BY t.x) AS value FROM t GROUP BY t.x ORDER BY t.x",
      syntax_limits(),
    ).unwrap(),
    qualify_group_collision_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(
    semantic(actual),
    semantic(
      window_aggregate_operand_expected(
        "{\"fn\":\"count\"}", "{\"fn\":\"lag\",\"expr\":{\"field\":\"aql_select_aggregate_0\"}}",
        "",
      ),
    ),
  )
}

///|
test "analytic SUM consumes ordinary grouped SUM with an explicit ROWS frame" {
  // Grouped sums are 41 and 10; the running sum must be 41 then 51.
  let actual = compile(
    @query.parse_query(
      "SELECT t.x, SUM(SUM(t.y)) OVER (ORDER BY t.x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS value FROM t GROUP BY t.x ORDER BY t.x",
      syntax_limits(),
    ).unwrap(),
    qualify_group_collision_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(
    semantic(actual),
    semantic(
      window_aggregate_operand_expected(
        "{\"fn\":\"sum\",\"field\":\"y\"}", "{\"fn\":\"sum\",\"field\":\"aql_select_aggregate_0\"}",
        ",\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"}",
      ),
    ),
  )
}

///|
fn checked_window_aggregate_operand(text : String) -> String raise {
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    qualify_group_collision_context(),
    construction_limits(),
  ).unwrap()
  check_window_operand_control(actual)
  semantic(actual)
}

///|
test "ordinary aggregate window operands compose with scalar named and clause scopes" {
  for
    text in [
      "SELECT t.x, COALESCE(LAG(COUNT(*)) OVER (ORDER BY t.x), 0) + 1 AS value FROM t GROUP BY t.x ORDER BY t.x",
      "SELECT t.x, LAG(SUM(t.y)) OVER w AS value FROM t GROUP BY t.x WINDOW w AS (ORDER BY t.x) ORDER BY t.x",
      "SELECT t.x FROM t GROUP BY t.x QUALIFY LAG(COUNT(*)) OVER (ORDER BY t.x) > 1 ORDER BY t.x",
      "SELECT t.x FROM t GROUP BY t.x ORDER BY LAG(COUNT(*)) OVER (ORDER BY t.x) NULLS LAST, t.x",
      "SELECT t.x, COUNTIF(COUNT(*) > 1) OVER (ORDER BY t.x ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS value FROM t GROUP BY t.x ORDER BY t.x",
      "SELECT LAG(COUNT(*)) OVER (ORDER BY COUNT(*)) AS value FROM t",
    ] {
    ignore(checked_window_aggregate_operand(text))
  }
}

///|
test "window argument extraction reuses evaluated aggregate slots without sibling aliases" {
  let actual = checked_window_aggregate_operand(
    "SELECT t.x AS original, COUNT(*) AS x, LAG(COUNT(*)) OVER (ORDER BY t.x) AS value FROM t GROUP BY t.x ORDER BY original",
  )
  assert_eq(actual.split("\"fn\":\"count\"").length(), 2)
  assert_true(actual.contains("\"expr\":{\"field\":\"aql_select_aggregate_"))
  assert_true(
    compile(
      @query.parse_query(
        "SELECT t.y AS invented, LAG(SUM(invented)) OVER (ORDER BY t.x) AS value FROM t GROUP BY t.x, t.y",
        syntax_limits(),
      ).unwrap(),
      qualify_group_collision_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "query ORDER window operands preserve alias arguments and qualified inputs" {
  let projected = checked_window_aggregate_operand(
    "SELECT t.y AS original, -t.y AS y FROM t GROUP BY t.y ORDER BY LAG(SUM(y)) OVER (ORDER BY original) NULLS LAST, original",
  )
  assert_true(projected.contains("\"aql_having_argument_"), msg=projected)
  assert_true(projected.contains("\"negate\":{\"field\":\"y\"}"), msg=projected)
  assert_false(
    projected.contains("\"field\":\"y\",\"fn\":\"sum\""),
    msg=projected,
  )
  let input = checked_window_aggregate_operand(
    "SELECT t.y AS original, -t.y AS y FROM t GROUP BY t.y ORDER BY LAG(SUM(t.y)) OVER (ORDER BY original) NULLS LAST, original",
  )
  assert_false(input.contains("\"aql_having_argument_"), msg=input)
  assert_true(input.contains("\"field\":\"y\",\"fn\":\"sum\""), msg=input)
}

///|
test "ordinary aggregate nesting and nested windows remain typed syntax refusals" {
  for
    text in [
      "SELECT SUM(SUM(t.y)) AS value FROM t", "SELECT COUNT(COUNT(*)) AS value FROM t",
    ] {
    assert_true(
      @query.parse_query(text, syntax_limits())
      is Err(
        {
          issue: @query.Syntax(
            "Ordinary aggregate cannot contain an aggregate call"
          ),
          ..
        }
      ),
      msg=text,
    )
  }
  for
    text in [
      "SELECT LAG(ROW_NUMBER() OVER (ORDER BY t.x)) OVER (ORDER BY t.x) AS value FROM t",
      "SELECT LAG(SUM(t.y) OVER (ORDER BY t.x ROWS CURRENT ROW)) OVER (ORDER BY t.x) AS value FROM t",
      "FROM t |> SELECT LAG(COUNT(*)) OVER (ORDER BY t.x) AS value",
    ] {
    assert_true(
      @query.parse_query(text, syntax_limits())
      is Err({ issue: @query.Syntax(_), .. }),
      msg=text,
    )
  }
}

///|
test "aggregate window operands retain the explicit frame implementation boundary" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT SUM(SUM(t.y)) OVER (ORDER BY t.x) AS value FROM t GROUP BY t.x",
        syntax_limits(),
      ).unwrap(),
      qualify_group_collision_context(),
      construction_limits(),
    )
    is Err(UnsupportedAnalytic),
  )
}

///|
test "aggregate window operands reject a grouped column as navigation offset" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT t.x, LAG(COUNT(*), t.x) OVER (ORDER BY t.x) AS value FROM t GROUP BY t.x",
        syntax_limits(),
      ).unwrap(),
      qualify_group_collision_context(),
      construction_limits(),
    )
    is Err(InvalidQuery),
  )
}
