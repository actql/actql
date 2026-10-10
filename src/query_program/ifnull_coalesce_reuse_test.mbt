///|
// Independently authored Programs retain the ordered, lazy coalesce operands.
fn coalesce_reuse_expected(grouped : Bool) -> @program.Program {
  let tail = if grouped {
    (
      #|{"from":"t","derive":{"aql_group_key_0":{"coalesce":[{"field":"x"},{"literal":0}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"value":"aql_group_key_0"},"n"],"as":"aql_gen_0"}
    )
  } else {
    (
      #|{"from":"t","derive":{"aql_query_expr_0":{"coalesce":[{"field":"x"},{"literal":0}]}}},{"select":[{"value":"aql_query_expr_0"}]},{"distinct":["value"]},{"sort":[{"field":"value","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}
    )
  }
  coalesce_reuse_program(
    tail,
    if grouped {
      "[\"value\",\"n\"]"
    } else {
      "[\"value\"]"
    },
  )
}

///|
fn coalesce_reuse_program(
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
// DISTINCT cannot restore an unselected input expression. The adopted
// semantic refusal is InvalidQuery, rather than an unimplemented ORDER path.
test "coalesce reuse preserves operands arity namespace and clause scope" {
  for
    ordered in [
      "COALESCE(x, 1)", "COALESCE(0, x)", "COALESCE(y, 0)", "COALESCE(x)", "COALESCE(x, 0, 1)",
      "NULLIF(x, 0)", "ACTQL.COALESCE(x, 0)",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT DISTINCT IFNULL(x, 0) AS value FROM t ORDER BY " + ordered,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=ordered,
    )
  }
  // Output x is x+1. ORDER must evaluate coalesce over that output, rather
  // than reuse the original input expression merely because its name matches.
  let actual = compile(
    @query.parse_query(
      "SELECT DISTINCT IFNULL(x, 0) AS original, x + 1 AS x FROM t ORDER BY COALESCE(x, 0)",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let expected = coalesce_reuse_program(
    (
      #|{"from":"t","derive":{"aql_query_expr_0":{"coalesce":[{"field":"x"},{"literal":0}]},"aql_query_expr_1":{"add":[{"field":"x"},{"literal":1}]}}},{"select":[{"original":"aql_query_expr_0"},{"x":"aql_query_expr_1"}]},{"distinct":["original","x"]},{"derive":{"aql_pipe_sort_4":{"coalesce":[{"field":"x"},{"literal":0}]}}},{"sort":[{"field":"aql_pipe_sort_4","dir":"asc","nulls":"first"}]},{"select":["original","x"],"as":"aql_gen_0"}
    ),
    "[\"original\",\"x\"]",
  )
  assert_eq(semantic(actual), semantic(expected))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "coalesce reuse preserves typed parameter holes and fallback demand" {
  let declarations = parameter_reference_declarations(
    "{\"p\":{\"type\":\"number\",\"nullable\":true}}",
  )
  let expected = coalesce_reuse_program(
    (
      #|{"from":"t","derive":{"aql_group_key_0":{"coalesce":[{"$param":"p"},{"divide":[{"literal":1},{"literal":0}]}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"value":"aql_group_key_0"},"n"],"as":"aql_gen_0"}
    ),
    "[\"value\",\"n\"]",
    parameters=true,
  )
  let actual = compile(
    @query.parse_query(
      "SELECT IFNULL(@p, 1 / 0) AS value, COUNT(*) AS n FROM t GROUP BY COALESCE(@p, 1 / 0)",
      syntax_limits(),
    ).unwrap(),
    { ..join_order_context(), parameter_declarations: Some(declarations), },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for value in ["{\"p\":2}", "{\"p\":null}"] {
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(grouped_in_parameter(value)),
        check_limits(),
      )
      is Checked(_),
    )
    assert_true(
      @check.check_parsed(
        expected,
        check_environment(),
        Some(grouped_in_parameter(value)),
        check_limits(),
      )
      is Checked(_),
    )
  }
}

///|
test "GROUP reuses IFNULL and two-operand COALESCE in either direction" {
  let expected = coalesce_reuse_expected(true)
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (selected, grouped) in [
      ("IFNULL(x, 0)", "COALESCE(t.x, 0)"),
      ("COALESCE(x, 0)", "IFNULL(t.x, 0)"),
      ("`ifnull`(x, 0)", "`CoAlEsCe`((t.x), 0)"),
    ] {
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

///|
test "DISTINCT ORDER reuses IFNULL and two-operand COALESCE in either direction" {
  let expected = coalesce_reuse_expected(false)
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (selected, ordered) in [
      ("IFNULL(x, 0)", "COALESCE(t.x, 0)"),
      ("COALESCE(x, 0)", "IFNULL(t.x, 0)"),
      ("`coalesce`(x, 0)", "`IfNuLl`((t.x), 0)"),
    ] {
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
