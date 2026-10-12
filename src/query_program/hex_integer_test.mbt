///|
test "hex SELECT agrees with an independent complete checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"literal":16}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for text in ["SELECT 0x10 AS id", "SELECT +0X10 AS id"] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
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
test "hex ORDER positions reuse visible evaluated slots" {
  let actual = checked_join_order("SELECT y, x FROM t ORDER BY 0x2 DESC, 0X1")
  assert_true(
    actual.contains(
      "\"sort\":[{\"dir\":\"desc\",\"field\":\"x\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"y\",\"nulls\":\"first\"}]",
    ),
  )
  assert_false(actual.contains("aql_query_sort_"))
}

///|
test "hex overflow and invalid column positions retain specific refusals" {
  for
    text in ["SELECT 0x20000000000000 AS id", "SELECT -0X20000000000000 AS id"] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(Expression({ issue: InvalidNumber, .. })),
    )
  }
  for ordinal in ["0x0", "0x3", "0x20000000000000"] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT y, x FROM t ORDER BY " + ordinal,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
    )
  }
}

///|
test "hex GROUP positions agree with an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x","y"],"aggregates":{"n":{"fn":"count"}}}},{"select":["y","x","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["y","x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT y, x, COUNT(*) AS n FROM t GROUP BY 0x2, 0X1",
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

///|
test "hex navigation offset retains the independent common analytic Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT id, LAG(amount, (0x2)) OVER (ORDER BY id) AS previous, LEAD(amount, ((@p))) OVER (ORDER BY id) AS next FROM orders ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    {
      ..values_context(),
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(grouped_analytic_offset_expected()))
}
