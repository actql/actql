///|
test "legacy Graph cannot silently treat a static label as a property" {
  let parsed = @query.parse_query(
    "FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(parsed, fixture_context(), construction_limits())
    is Err(UnsupportedGraph),
  )
}
