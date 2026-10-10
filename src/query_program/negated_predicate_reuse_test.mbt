///|
// Independently authored complete Programs use the common not/test nodes,
// rather than generating expected expressions through the query lowerer.
fn negated_predicate_expected(key : String, grouped : Bool) -> @program.Program {
  let tail = if grouped {
    (
      #|{"from":"t","derive":{"aql_group_key_0":
    ) +
    key +
    (
      #|}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"value":"aql_group_key_0"},"n"],"as":"aql_gen_0"}
    )
  } else {
    (
      #|{"from":"t","derive":{"aql_query_expr_0":
    ) +
    key +
    (
      #|}},{"select":[{"value":"aql_query_expr_0"}]},{"distinct":["value"]},{"sort":[{"field":"value","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}
    )
  }
  negated_predicate_program(
    tail,
    if grouped {
      "[\"value\",\"n\"]"
    } else {
      "[\"value\"]"
    },
  )
}

///|
fn negated_predicate_program(
  tail : String,
  fields : String,
  parameters? : Bool = false,
) -> @program.Program {
  let declarations = if parameters {
    ",\"params\":{\"p\":{\"type\":\"number\",\"nullable\":true}}"
  } else {
    ""
  }
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\"" +
    declarations +
    (
      #|,"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},
    ) +
    tail +
    (
      #|],"results":{"rows":{"from":"aql_gen_0","fields":
    ) +
    fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn negated_predicate_cases() -> Array[(String, String, String)] {
  [
    (
      "x IS NOT NULL", "NOT (t.x IS NULL)", "{\"not\":{\"is_null\":{\"field\":\"x\"}}}",
    ),
    (
      "(x > 1) IS NOT TRUE", "NOT (((t.x > 1) IS TRUE))", "{\"not\":{\"is_true\":{\"gt\":[{\"field\":\"x\"},{\"literal\":1}]}}}",
    ),
    (
      "(x > 1) IS NOT FALSE", "NOT ((t.x > 1) IS FALSE)", "{\"not\":{\"is_false\":{\"gt\":[{\"field\":\"x\"},{\"literal\":1}]}}}",
    ),
    (
      "(x > 1) IS NOT UNKNOWN", "NOT ((t.x > 1) IS UNKNOWN)", "{\"not\":{\"is_unknown\":{\"gt\":[{\"field\":\"x\"},{\"literal\":1}]}}}",
    ),
    (
      "x IS NOT DISTINCT FROM 2", "NOT (t.x IS DISTINCT FROM 2)", "{\"not\":{\"is_distinct_from\":[{\"field\":\"x\"},{\"literal\":2}]}}",
    ),
  ]
}

///|
test "GROUP IS NOT and explicit NOT reuse one checked predicate value" {
  for (direct, explicit, key) in negated_predicate_cases() {
    let expected = negated_predicate_expected(key, true)
    assert_true(
      @check.check_parsed(expected, check_environment(), None, check_limits())
      is Checked(_),
    )
    for (selected, grouped) in [(direct, explicit), (explicit, direct)] {
      let actual = compile(
        @query.parse_query(
          "SELECT " +
          selected +
          " AS value, COUNT(*) AS n FROM t GROUP BY " +
          grouped,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      assert_true(
        @check.check_parsed(actual, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}

///|
test "DISTINCT ORDER IS NOT and explicit NOT reuse the evaluated output" {
  for (direct, explicit, key) in negated_predicate_cases() {
    let expected = negated_predicate_expected(key, false)
    assert_true(
      @check.check_parsed(expected, check_environment(), None, check_limits())
      is Checked(_),
    )
    for (selected, ordered) in [(direct, explicit), (explicit, direct)] {
      let actual = compile(
        @query.parse_query(
          "SELECT DISTINCT " + selected + " AS value FROM t ORDER BY " + ordered,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
      assert_true(
        @check.check_parsed(actual, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}

///|
test "negated predicate reuse retains mode operands and output scope" {
  for
    (selected, ordered) in [
      ("x IS NOT NULL", "x IS NULL"),
      ("(x > 1) IS NOT TRUE", "NOT ((x > 1) IS FALSE)"),
      ("(x > 1) IS NOT UNKNOWN", "NOT ((x > 2) IS UNKNOWN)"),
      ("x IS NOT DISTINCT FROM 2", "NOT (x IS DISTINCT FROM 1)"),
      ("x IS NOT DISTINCT FROM 2", "NOT (x = 2)"),
      ("x IS NOT NULL", "NOT (y IS NULL)"),
      ("x IS NOT NULL", "NOT (NOT (x IS NULL))"),
    ] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT DISTINCT " + selected + " AS value FROM t ORDER BY " + ordered,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedOrdering),
      msg=ordered,
    )
  }
  let actual = compile(
    @query.parse_query(
      "SELECT DISTINCT x IS NOT NULL AS x FROM t ORDER BY NOT (x IS NULL)",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  // The input x is numeric but the output x is Boolean. Evaluate the new
  // ORDER test over that output rather than reusing the test of numeric x.
  let expected = negated_predicate_program(
    (
      #|{"from":"t","derive":{"aql_query_expr_0":{"not":{"is_null":{"field":"x"}}}}},{"select":[{"x":"aql_query_expr_0"}]},{"distinct":["x"]},{"derive":{"aql_pipe_sort_2":{"not":{"is_null":{"field":"x"}}}}},{"sort":[{"field":"aql_pipe_sort_2","dir":"asc","nulls":"first"}]},{"select":["x"],"as":"aql_gen_0"}
    ),
    "[\"x\"]",
  )
  assert_eq(semantic(actual), semantic(expected))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "negated predicate reuse retains parameter holes and Boolean test typing" {
  let expected = negated_predicate_program(
    (
      #|{"from":"t","derive":{"aql_group_key_0":{"not":{"is_distinct_from":[{"field":"x"},{"$param":"p"}]}}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"value":"aql_group_key_0"},"n"],"as":"aql_gen_0"}
    ),
    "[\"value\",\"n\"]",
    parameters=true,
  )
  let actual = compile(
    @query.parse_query(
      "SELECT x IS NOT DISTINCT FROM @p AS value, COUNT(*) AS n FROM t GROUP BY NOT (t.x IS DISTINCT FROM (@p))",
      syntax_limits(),
    ).unwrap(),
    {
      ..join_order_context(),
      parameter_declarations: Some(literal_membership_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for value in ["{\"p\":2}", "{\"p\":null}"] {
    for program in [actual, expected] {
      assert_true(
        @check.check_parsed(
          program,
          check_environment(),
          Some(grouped_in_parameter(value)),
          check_limits(),
        )
        is Checked(_),
      )
    }
  }
  let invalid = compile(
    @query.parse_query(
      "SELECT DISTINCT x IS NOT TRUE AS value FROM t ORDER BY NOT (t.x IS TRUE)",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(
    semantic(invalid),
    semantic(
      negated_predicate_expected(
        "{\"not\":{\"is_true\":{\"field\":\"x\"}}}", false,
      ),
    ),
  )
  guard @check.check_parsed(invalid, check_environment(), None, check_limits())
    is Rejected(diagnostic) else {
    fail("IS TRUE must still require a Boolean input")
  }
  assert_eq(@check.diagnostic_category(diagnostic), @check.InvalidInput)
}
