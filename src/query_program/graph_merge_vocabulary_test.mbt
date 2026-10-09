///|
test "uppercase union merge lowers to the independent complete Program" {
  let expected = graph_union_expected()
  check_graph_union_source(expected)
  let actual = compile_data_set(
    graph_union_prefix() +
    "FROM g |> UNION_GRAPHS(WITH: [g, g], MERGE: {NODE_PROPERTIES: {p: 'number_sum'}}) |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(actual), semantic(expected))
  check_graph_union_source(actual)
}

///|
test "quoted subtraction merge lowers to the independent complete Program" {
  let expected = graph_subtraction_expected()
  check_graph_union_source(expected)
  let actual = compile_data_set(
    graph_union_prefix() +
    "FROM g |> SUBTRACT_GRAPHS(WITH: g, MERGE: {`Node_Properties`: {p: 'number_sum'}}) |> node_rows() |> SELECT p, node_key",
  )
  assert_eq(semantic(actual), semantic(expected))
  check_graph_union_source(actual)
}
