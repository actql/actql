///|
// Independently authored: the original nullable text is measured once before
// grouping, and SELECT uses that evaluated key rather than the dropped input.
fn scalar_alias_group_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","derive":{"aql_group_key_0":{"len":{"field":"name"}}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"aql_select_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_query_expr_0":{"add":[{"field":"aql_select_aggregate_0"},{"field":"aql_group_key_0"}]}}},{"select":[{"n":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "GROUP scalar aliases share the independent evaluated key" {
  let expected = scalar_alias_group_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("the independent nullable length control requires no acquisition")
  }
  for
    source in [
      "SELECT COUNT(*) + CHAR_LENGTH(name) AS n FROM objects GROUP BY CHAR_LENGTH(name)",
      "SELECT COUNT(*) + CHARACTER_LENGTH(name) AS n FROM objects GROUP BY CHAR_LENGTH(name)",
      "SELECT COUNT(*) + CHARACTER_LENGTH(objects.name) AS n FROM objects GROUP BY CHAR_LENGTH(name)",
    ] {
    let actual = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression({ issue: @expression.UnknownReference, .. })) =>
        fail("UnknownReference: " + source)
      Err(_) => fail("another source compilation failure: " + source)
    }
    assert_eq(semantic(actual), semantic(expected), msg=source)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
}

///|
test "GROUP scalar alias reuse preserves receiver and function differences" {
  for
    source in [
      "SELECT COUNT(*) + CHAR_LENGTH(name) AS n FROM objects GROUP BY CHARACTER_LENGTH(objects.id)",
      "SELECT COUNT(*) + ABS(id) AS n FROM objects GROUP BY CEIL(id)", "SELECT COUNT(*) + CHAR_LENGTH(old.name) AS n FROM objects AS current GROUP BY CHARACTER_LENGTH(current.name)",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "GROUP scalar aliases cannot hide invalid function arity" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT COUNT(*) + CHARACTER_LENGTH(1, 1) AS n FROM objects GROUP BY CHAR_LENGTH(name)",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.InvalidArguments, .. })),
  )
}
