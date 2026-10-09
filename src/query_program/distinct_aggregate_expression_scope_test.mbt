///|
// Independent full Program: the resolved aggregate value is also its DISTINCT
// order key. Qualification never supplies a second value or another argument.
fn distinct_conditional_scope_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","derive":{"aql_aggregate_sort_5":{"coalesce":[{"field":"name"},{"literal":"missing"}]}}},{"group":{"by":[],"aggregates":{"names":{"fn":"string_agg","expr":{"coalesce":[{"field":"name"},{"literal":"missing"}]},"distinct":true,"max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_5","dir":"asc","nulls":"first"}],"delimiter":"|"}}}},{"select":["names"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["names"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "DISTINCT conditional order resolves qualified operands to the same input value" {
  let expected = distinct_conditional_scope_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent computed argument/order Program must check")
  }
  for
    text in [
      "SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(objects.name, 'missing')) AS names FROM objects",
      "SELECT STRING_AGG(DISTINCT IFNULL(o.name, 'missing'), '|' ORDER BY IFNULL(`o`.`NAME`, 'missing')) AS names FROM objects AS o",
      "FROM objects AS o |> AGGREGATE STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(o.name, 'missing')) AS names",
    ] {
    let actual = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedAggregate) => fail(text + ": UnsupportedAggregate")
      Err(_) => fail(text + ": another compile refusal")
    }
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "DISTINCT conditional members resolve their original receiver inside the tree" {
  let key = "{\"coalesce\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":0}]}"
  let expected = distinct_signed_order_expected(key)
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (argument, order) in [
      ("IFNULL(payload.score, 0)", "IFNULL(o.payload.score, 0)"),
      ("IFNULL((payload).score, 0)", "IFNULL((o.payload).`SCORE`, 0)"),
      ("IFNULL(o.payload.score, 0)", "IFNULL(((payload)).score, 0)"),
    ] {
    let actual = compile(
      @query.parse_query(
        "FROM objects AS o |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(DISTINCT " +
        argument +
        " IGNORE NULLS ORDER BY " +
        order +
        " DESC) AS items",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "DISTINCT computed order preserves operands operators literals and snapshot scope" {
  for
    text in [
      "SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(objects.name, 'other')) AS names FROM objects",
      "SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(objects.id, 'missing')) AS names FROM objects",
      "SELECT ARRAY_AGG(DISTINCT IFNULL(payload.score, 0) IGNORE NULLS ORDER BY IFNULL(other.score, 0)) AS items FROM objects",
      "SELECT ARRAY_AGG(DISTINCT IF(id = 1, 0, payload.score) IGNORE NULLS ORDER BY IF(objects.id != 1, 0, objects.payload.score)) AS items FROM objects",
      "SELECT ARRAY_AGG(DISTINCT CASE WHEN id = 1 THEN 0 ELSE payload.score END IGNORE NULLS ORDER BY CASE WHEN objects.id = 2 THEN 0 ELSE objects.payload.score END) AS items FROM objects",
      "FROM objects AS before |> SET name = 'changed' |> AGGREGATE STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(before.name, 'missing')) AS names",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=text,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ARRAY_AGG(DISTINCT IFNULL((payload).score, 0) IGNORE NULLS ORDER BY IFNULL(payload.score, 0)) AS items FROM objects AS payload",
        syntax_limits(),
      ).unwrap(),
      group_receiver_scope_context(),
      construction_limits(),
    )
    is Err(UnsupportedAggregate),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(DISTINCT IFNULL(name, @fallback), '|' ORDER BY IFNULL(objects.name, @other)) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      {
        ..aggregate_property_order_context(),
        parameter_declarations: Some(
          parameter_reference_declarations(
            "{\"fallback\":{\"type\":\"string\",\"nullable\":true},\"other\":{\"type\":\"string\",\"nullable\":true}}",
          ),
        ),
      },
      construction_limits(),
    )
    is Err(UnsupportedAggregate),
  )
}

///|
test "equivalent qualified conditional order keys share their admitted input slot" {
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","derive":{"aql_aggregate_sort_6":{"coalesce":[{"field":"name"},{"literal":"missing"}]}}},{"group":{"by":[],"aggregates":{"names":{"fn":"string_agg","field":"name","max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_6","dir":"asc","nulls":"first"}],"delimiter":"|"},"reverse":{"fn":"string_agg","field":"name","max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_6","dir":"desc","nulls":"last"}],"delimiter":"|"}}}},{"select":["names","reverse"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["names","reverse"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "SELECT STRING_AGG(name, '|' ORDER BY IFNULL(name, 'missing')) AS names, STRING_AGG(name, '|' ORDER BY IFNULL(o.name, 'missing') DESC) AS reverse FROM objects AS o",
      syntax_limits(),
    ).unwrap(),
    aggregate_property_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}
