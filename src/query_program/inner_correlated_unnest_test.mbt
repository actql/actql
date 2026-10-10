///|
fn inner_correlated_unnest_control() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    correlated_unnest_seed() +
    "," +
    (
      #|{"from":"parents","derive":{"aql_unnest_array_4":{"field":"items"}}},{"unnest":{"column":"aql_unnest_array_4","as":"aql_unnest_element_5","with_index":"aql_unnest_offset_6"}},{"filter":{"eq":[{"field":"aql_unnest_element_5"},{"field":"id"}]}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"aql_unnest_offset_6","dir":"asc","nulls":"first"}]},{"select":["id",{"element":"aql_unnest_element_5"},{"position":"aql_unnest_offset_6"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "INNER correlated expansion has an independently checked common control" {
  assert_true(
    @check.check_parsed(
      inner_correlated_unnest_control(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "SQL INNER correlated expansion preserves the parent and element ON predicate" {
  for
    text in [
      "SELECT p.id, element, position FROM parents p INNER JOIN UNNEST(p.items) element WITH OFFSET position ON element = p.id ORDER BY p.id, position",
      "SELECT `p`.id, `element`, `position` FROM parents `p` JOIN UNNEST(`p`.items) `element` WITH OFFSET `position` ON `element` = `p`.id ORDER BY `p`.id, `position`",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      correlated_unnest_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(inner_correlated_unnest_control()))
  }
}

///|
test "INNER correlation retains ordinary continuations and immutable ranges" {
  for
    text in [
      "SELECT p.id, element, position FROM parents p JOIN UNNEST(p.items) element WITH OFFSET position ON element = p.id JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10 ORDER BY position",
      "FROM parents p |> SET id = 99 |> INNER JOIN UNNEST(p.items) element ON element = p.id |> SELECT id AS current, p.id AS original, element",
      "FROM parents p |> SELECT id, items |> UNION ALL (FROM parents p |> SELECT id, items) |> JOIN UNNEST(items) element ON element = id |> SELECT id, element",
      "SELECT p.id, element FROM parents p INNER JOIN UNNEST(p.items) element", "FROM parents p |> INNER JOIN UNNEST(p.items) element |> SELECT p.id, element",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      correlated_unnest_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("INNER correlation must use ordinary checked operations")
    }
  }
}

///|
test "INNER correlation does not reinterpret unsupported join clauses" {
  for
    text in [
      "SELECT element FROM parents p CROSS JOIN UNNEST(p.items) element ON TRUE",
      "SELECT element FROM parents p INNER JOIN UNNEST(p.items) element USING (id)",
      "SELECT element FROM parents p INNER JOIN UNNEST(p.items) element MAX_OUTPUT_ROWS 10",
      "SELECT element FROM parents p LEFT JOIN UNNEST(p.items) element ON TRUE",
    ] {
    assert_true(@query.parse_query(text, syntax_limits()) is Err(_), msg=text)
  }
}

///|
test "Pipe INNER correlated expansion preserves the parent and element ON predicate" {
  let actual = compile(
    @query.parse_query(
      "FROM parents p |> JOIN UNNEST(p.items) element WITH OFFSET position ON element = p.id |> SELECT p.id, element, position |> ORDER BY p.id, position",
      syntax_limits(),
    ).unwrap(),
    correlated_unnest_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(inner_correlated_unnest_control()))
}
