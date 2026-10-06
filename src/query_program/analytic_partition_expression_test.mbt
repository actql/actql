///|
fn analytic_partition_expression_expected() -> @program.Program {
  // The private suffix is the four input names plus reserved analytic pos.
  // This complete Program is authored independently of the source compiler.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","derive":{"aql_analytic_sort_5":{"gt":[{"field":"amount"},{"literal":1}]}}},{"analytic":{"partition_by":["aql_analytic_sort_5"],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"pos":{"fn":"row_number"}}}},{"select":["id","pos"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn checked_partition_expression(text : String) -> @program.Program raise {
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    partition_property_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("partition expressions use the common analytic checker")
  }
  program
}

///|
test "partition expressions share evaluated input slots across partition order and windows" {
  let wire = semantic(
    checked_partition_expression(
      "SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing'), COALESCE(payload.bucket, 'missing') ORDER BY COALESCE(payload.bucket, 'missing'), id) AS pos, RANK() OVER (PARTITION BY COALESCE(payload.bucket, 'missing') ORDER BY id) AS ranking FROM objects ORDER BY id",
    ),
  )
  assert_eq(wire.split("\"coalesce\":").length(), 2)
  assert_eq(wire.split("\"property\":").length(), 2)
  assert_true(
    wire.contains(
      "\"partition_by\":[\"aql_analytic_sort_5\",\"aql_analytic_sort_5\"]",
    ),
  )
  assert_eq(wire.split("\"analytic\":").length(), 3)
}

///|
test "partition expressions preserve input receiver and immutable Pipe range snapshots" {
  let wire = semantic(
    checked_partition_expression(
      "SELECT id, other AS payload, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing') ORDER BY id) AS pos FROM objects ORDER BY id",
    ),
  )
  assert_true(wire.contains("\"value\":{\"field\":\"payload\"}"))
  assert_false(wire.contains("\"value\":{\"field\":\"other\"}"))
  let current = semantic(
    checked_partition_expression(
      "FROM objects AS original |> SET payload = other |> SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(original.payload.bucket, 'missing') ORDER BY id) AS before, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing') ORDER BY id) AS current |> ORDER BY id",
    ),
  )
  assert_true(current.contains("\"value\":{\"field\":\"payload\"}"))
  assert_true(current.contains("\"value\":{\"field\":\"aql_pipe_set_3\"}"))
}

///|
test "partition expressions reject constants instead of treating them as ordinals" {
  for
    key in [
      "1", "(1)", "1 + 2", "TRUE", "NULL", "'x'", "COALESCE(NULL, 'x')", "@p",
    ] {
    let query = @query.parse_query(
      "SELECT ROW_NUMBER() OVER (PARTITION BY " +
      key +
      " ORDER BY id) AS pos FROM objects",
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile(query, partition_property_context(), construction_limits())
      is Err(UnsupportedAnalytic),
      msg=key,
    )
  }
}

///|
test "partition expressions retain ordinary reference errors and checker key typing" {
  for key in ["COALESCE(missing, 'x')", "COALESCE(sibling.bucket, 'x')"] {
    let query = @query.parse_query(
      "SELECT other AS sibling, ROW_NUMBER() OVER (PARTITION BY " +
      key +
      " ORDER BY id) AS pos FROM objects",
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile(query, partition_property_context(), construction_limits())
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=key,
    )
  }
  for
    key in ["COALESCE(payload, other)", "payload.missing = 'x'", "id + 'x' > 0"] {
    let program = compile(
      @query.parse_query(
        "SELECT ROW_NUMBER() OVER (PARTITION BY " +
        key +
        " ORDER BY id) AS pos FROM objects",
        syntax_limits(),
      ).unwrap(),
      partition_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg=key,
    )
  }
}

///|
test "analytic partition expressions match an independently checked complete Program" {
  let expected = analytic_partition_expression_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Values partition Program must be closed")
  }
  for
    text in [
      "SELECT id, ROW_NUMBER() OVER (PARTITION BY amount > 1 ORDER BY id) AS pos FROM orders ORDER BY id",
      "FROM orders |> SELECT id, ROW_NUMBER() OVER (PARTITION BY (amount > 1) ORDER BY id) AS pos |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}
