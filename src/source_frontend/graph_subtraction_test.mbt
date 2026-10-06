///|
test "Graph subtraction uses the existing public script route" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let source = "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); DATA remaining = FROM g |> subtract_graphs(with: g); FROM remaining |> node_rows() |> SELECT p"
  let result = lower(source, Text, Some(context)).unwrap()
  assert_true(
    result.document.contains("\"subtract_graphs\":{\"with\":\"aql_data_2\"}"),
  )
}
