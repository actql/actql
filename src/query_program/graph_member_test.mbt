///|
test "Graph member spelling binds to the independently checked projection" {
  let expected = graph_projection_property_expected()
  guard @check.check_parsed(
      expected,
      graph_rows_environment(),
      None,
      check_limits(),
    )
    is Checked(_) else {
    fail("independent Graph Program must check")
  }
  for
    tail in [
      "SELECT a.id AS id, a.payload.score AS score", "SELECT a.id AS id, a.payload.SCORE AS score",
      "SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`ScOrE` AS score",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(
        graph_projection_property_source(tail),
        syntax_limits(),
      ).unwrap(),
      graph_projection_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=tail)
    guard @check.check_parsed(
        actual,
        graph_rows_environment(),
        None,
        check_limits(),
      )
      is Checked(_) else {
      fail("source Graph projection must pass ordinary checking")
    }
  }
}

///|
test "Graph member spelling is retained through an ordinary projected receiver" {
  let actual = compile_query_script(
    @query.parse_query_script(
      graph_projection_property_source(
        "SELECT a.id AS id, a.payload AS kept |> SELECT id, kept.SCORE AS score",
      ),
      syntax_limits(),
    ).unwrap(),
    graph_projection_property_context(),
    construction_limits(),
  ).unwrap()
  // Transform the existing handwritten machine fixture, never compiler output.
  // The inserted SELECT and following derive/select are independently specified.
  let expected_text = semantic(graph_projection_property_expected())
    .replace(
      old="{\"derive\":{\"aql_query_expr_1\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}},\"from\":\"aql_keyed_seeds_3\"}",
      new="{\"from\":\"aql_keyed_seeds_3\",\"select\":[\"id\",{\"kept\":\"payload\"}]},{\"derive\":{\"aql_pipe_expr_2\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"kept\"}}}}}",
    )
    .replace(old="aql_query_expr_1", new="aql_pipe_expr_2")
  let expected = @program.parse(
    expected_text,
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  guard @check.check_parsed(
      actual,
      graph_rows_environment(),
      None,
      check_limits(),
    )
    is Checked(_) else {
    fail("projected Graph receiver must pass ordinary checking")
  }
}
