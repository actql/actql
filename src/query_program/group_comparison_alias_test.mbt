///|
test "GROUP not-equal spellings reuse the independent checked Boolean key" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"neq":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"aql_select_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_query_expr_0":{"add":[{"field":"aql_select_aggregate_0"},{"if":[{"field":"aql_group_key_0"},{"literal":1},{"literal":0}]}]}}},{"select":[{"n":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for (selected, grouped) in [("!=", "!="), ("!=", "<>"), ("<>", "!=")] {
    let source = "SELECT COUNT(*) + IF(pair.x " +
      selected +
      " 1, 1, 0) AS n FROM pair GROUP BY x " +
      grouped +
      " 1"
    let actual = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression({ issue: @expression.UnknownReference, .. })) =>
        fail("UnknownReference: " + source)
      Err(_) => fail("another failure: " + source)
    }
    assert_eq(semantic(actual), semantic(expected), msg=source)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "GROUP operator alias reuse does not equate distinct receivers or polarity" {
  for
    source in [
      "SELECT COUNT(*) + IF(x != 1, 1, 0) AS n FROM pair GROUP BY y <> 1", "SELECT COUNT(*) + IF(x != 1, 1, 0) AS n FROM pair GROUP BY x = 1",
      "SELECT COUNT(*) + IF(x < 1, 1, 0) AS n FROM pair GROUP BY x <= 1", "SELECT COUNT(*) + IF(old.x != 1, 1, 0) AS n FROM pair AS current GROUP BY current.x <> 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}
