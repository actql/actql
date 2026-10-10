///|
fn membership_reuse_expected(
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
test "GROUP literal list and unannotated IN UNNEST reuse one checked key" {
  let expected = membership_reuse_expected(
    (
      #|{"from":"t","derive":{"aql_group_key_0":{"in":[{"field":"x"},{"literal":[1,2,2,null]}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"included":"aql_group_key_0"},"n"],"as":"aql_gen_0"}
    ),
    "[\"included\",\"n\"]",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (selected, grouped) in [
      ("x IN (1,2,2,NULL)", "x IN UNNEST([1,2,2,NULL])"),
      ("t.x IN UNNEST(ARRAY[1,2,2,NULL])", "x IN (1,2,2,NULL)"),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT " +
        selected +
        " AS included, COUNT(*) AS n FROM t GROUP BY " +
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
test "DISTINCT ORDER literal list and IN UNNEST reuse the evaluated output" {
  let expected = membership_reuse_expected(
    (
      #|{"from":"t","derive":{"aql_query_expr_0":{"not_in":[{"field":"x"},{"literal":[1,2,2,null]}]}}},{"select":[{"included":"aql_query_expr_0"}]},{"distinct":["included"]},{"sort":[{"field":"included","dir":"asc","nulls":"last"}],"as":"aql_gen_0"}
    ),
    "[\"included\"]",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (selected, ordered) in [
      ("x NOT IN (1,2,2,NULL)", "x NOT IN UNNEST([1,2,2,NULL])"),
      ("t.x NOT IN UNNEST(ARRAY[1,2,2,NULL])", "x NOT IN (1,2,2,NULL)"),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT DISTINCT " +
        selected +
        " AS included FROM t ORDER BY " +
        ordered +
        " NULLS LAST",
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
test "membership reuse retains immediate parameters and Pipe input meaning" {
  let grouped = membership_reuse_expected(
    (
      #|{"from":"t","derive":{"aql_group_key_0":{"in":[{"field":"x"},{"literal":[{"$param":"p"},2,null]}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"included":"aql_group_key_0"},"n"],"as":"aql_gen_0"}
    ),
    "[\"included\",\"n\"]",
    parameters=true,
  )
  let distinct = membership_reuse_expected(
    (
      #|{"from":"t","derive":{"aql_query_expr_0":{"not_in":[{"field":"x"},{"literal":[{"$param":"p"},2,null]}]}}},{"select":[{"included":"aql_query_expr_0"}]},{"distinct":["included"]},{"sort":[{"field":"included","dir":"asc","nulls":"last"}],"as":"aql_gen_0"}
    ),
    "[\"included\"]",
    parameters=true,
  )
  for
    (source, expected) in [
      (
        "SELECT x IN ((@p),2,NULL) AS included, COUNT(*) AS n FROM t GROUP BY t.x IN UNNEST(ARRAY[(@p),2,NULL])",
        grouped,
      ),
      (
        "FROM t |> SELECT DISTINCT x NOT IN UNNEST([((@p)),2,NULL]) AS included |> ORDER BY t.x NOT IN (@p,2,NULL) NULLS LAST",
        distinct,
      ),
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      {
        ..join_order_context(),
        parameter_declarations: Some(literal_membership_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for value in ["{\"p\":1}", "{\"p\":null}"] {
      for program in [expected, actual] {
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
  }
}

///|
// DISTINCT cannot restore an unselected input expression. The adopted
// semantic refusal is InvalidQuery, rather than an unimplemented ORDER path.
test "membership reuse cannot erase modes annotations computations or alias changes" {
  for
    ordered in [
      "x NOT IN UNNEST([1,2])", "x IN UNNEST([2,1])", "x IN UNNEST([1,2,2])", "x IN UNNEST(ARRAY<FLOAT64>[1,2])",
      "x IN UNNEST([1,1+1])", "y IN UNNEST([1,2])",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT DISTINCT x IN (1,2) AS included FROM t ORDER BY " + ordered,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=ordered,
    )
  }
  let actual = compile(
    @query.parse_query(
      "SELECT DISTINCT x IN (1,2) AS x FROM t ORDER BY x IN UNNEST([1,2])",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  // DISTINCT retained a Boolean output x. ORDER must compute from that
  // output, not reuse the membership of the original numeric input x.
  let expected = membership_reuse_expected(
    (
      #|{"from":"t","derive":{"aql_query_expr_0":{"in":[{"field":"x"},{"literal":[1,2]}]}}},{"select":[{"x":"aql_query_expr_0"}]},{"distinct":["x"]},{"derive":{"aql_pipe_sort_2":{"in":[{"field":"x"},{"literal":[1,2]}]}}},{"sort":[{"field":"aql_pipe_sort_2","dir":"asc","nulls":"first"}]},{"select":["x"],"as":"aql_gen_0"}
    ),
    "[\"x\"]",
  )
  assert_eq(semantic(actual), semantic(expected))
  guard @check.check_parsed(actual, check_environment(), None, check_limits())
    is Rejected(diagnostic) else {
    fail("Boolean output membership cannot compare numeric elements")
  }
  guard @check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
    raise @check.diagnostic_cause(diagnostic)
  }
  assert_true(
    issue.kind
    is Operation(Expression(TypeMismatch("membership element domain"))),
  )
}
