///|
// Complete author-written Program: equivalent nullable property receivers
// share one value within the immutable OVER input scope. Key lists retain
// their authored repetitions and direction; no result is compiler-generated.
fn window_key_receiver_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    partition_property_seed() +
    (
      #|,{"from":"objects","derive":{"aql_analytic_sort_5":{"coalesce":[{"property":{"value":{"field":"payload"},"name":"bucket"}},{"literal":"missing"}]}}},{"analytic":{"partition_by":["aql_analytic_sort_5","aql_analytic_sort_5"],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"pos":{"fn":"row_number"}}}},{"analytic":{"partition_by":["aql_analytic_sort_5"],"order_by":[{"field":"id","dir":"desc","nulls":"last"}],"functions":{"ranking":{"fn":"rank"}}}},{"select":["id","pos","ranking"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","pos","ranking"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "OVER key reuse proves equivalent property receivers against a complete Program" {
  let expected = window_key_receiver_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent OVER Program is closed")
  }
  for
    text in [
      "SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing'), COALESCE((objects.payload).`BUCKET`, 'missing') ORDER BY id) AS pos, RANK() OVER (PARTITION BY COALESCE((payload).bucket, 'missing') ORDER BY id DESC) AS ranking FROM objects ORDER BY id",
      "FROM objects |> SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing'), COALESCE((objects.payload).`BUCKET`, 'missing') ORDER BY id) AS pos, RANK() OVER (PARTITION BY COALESCE((payload).bucket, 'missing') ORDER BY id DESC) AS ranking |> ORDER BY id",
    ] {
    assert_eq(
      semantic(checked_partition_expression(text)),
      semantic(expected),
      msg=text,
    )
  }
}

///|
test "OVER key reuse retains distinct current and original Pipe values" {
  let body = semantic(
    checked_partition_expression(
      "FROM objects AS original |> SET payload = other |> SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE((original.payload).bucket, 'missing') ORDER BY id) AS before, RANK() OVER (PARTITION BY COALESCE(payload.bucket, 'missing') ORDER BY id) AS current |> ORDER BY id",
    ),
  )
  assert_eq(body.split("\"coalesce\":").length() - 1, 2)
  assert_true(body.contains("\"value\":{\"field\":\"payload\"}"))
  assert_true(body.contains("\"value\":{\"field\":\"aql_pipe_set_3\"}"))
}

///|
test "OVER key reuse distinguishes explicit object and Relation range receivers" {
  let program = compile(
    @query.parse_query(
      "SELECT id, ROW_NUMBER() OVER (ORDER BY (payload).score, id) AS pos, RANK() OVER (ORDER BY payload.score DESC, id) AS ranking FROM objects AS payload ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    group_receiver_scope_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Checked(_),
  )
  let body = semantic(program)
  assert_eq(body.split("\"property\":").length() - 1, 1)
  assert_true(body.contains("\"field\":\"score\""))
  assert_true(body.contains("\"value\":{\"field\":\"payload\"}"))
}

///|
test "OVER key reuse preserves bounded comparison and original source origin" {
  let query = @query.parse_query(
    "SELECT ROW_NUMBER() OVER (ORDER BY amount + 1, (orders.amount + 1)) AS pos FROM orders",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, values_context(), {
      ..construction_limits(),
      max_expression_work: 6,
    })
    is Err(Expression({ issue: @expression.WorkLimit, origin: Some(_), })),
  )
}
