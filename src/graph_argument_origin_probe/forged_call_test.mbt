///|
test "external call ownership control" {
  let query = @syntax.parse_query(
    "FROM g |> components(kind: 'weak')",
    syntax_limits(),
  ).unwrap()
  let call = graph_call(query)
  let observed : @syntax.SgaCall = call
  assert_eq(observed.operation, "components")
}
