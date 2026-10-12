///|
test "a static label does not supply the missing admitted Graph producer" {
  let parsed = @query.parse_query(
    "FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id",
    syntax_limits(),
  ).unwrap()
  assert_true(
    exact_unresolved_relation(
      compile(parsed, fixture_context(), construction_limits()),
      [("g", false)],
    ),
  )
}
