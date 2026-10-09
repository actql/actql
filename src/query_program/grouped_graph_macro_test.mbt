///|
test "grouping a Graph binding preserves the independently checked identity predicate" {
  let expected = graph_projection_property_expected(with_filter=true)
  match
    @check.check_parsed(
      expected,
      graph_rows_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    _ => fail("the independent Values Graph control is closed")
  }
  for argument in ["a", "(a)", "(((a)))", "(`A`)"] {
    let source = graph_projection_property_source(
      "WHERE NODE_ID(" +
      argument +
      ") IS NOT NULL AND a.payload.score > 10 |> SELECT a.id AS id, a.payload.score AS score",
    )
    let actual = match
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        graph_projection_property_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression(diagnostic)) =>
        fail(
          "Graph binding " +
          argument +
          " failed: " +
          @debug.to_string(diagnostic.issue),
        )
      Err(_) => fail("unexpected Graph source refusal")
    }
    assert_eq(semantic(actual), semantic(expected), msg=argument)
  }
}
