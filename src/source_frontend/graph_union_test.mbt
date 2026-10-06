///|
test "Graph union uses the existing script source route" {
  let text = "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); DATA merged = FROM g |> union_graphs(with: [g, g], merge: {node_properties: {p: 'number_sum'}}); FROM merged |> node_rows() |> SELECT p"
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let actual = lower(text, Text, Some(context)).unwrap()
  assert_true(
    actual.document.contains(
      "\"union_graphs\":{\"with\":[\"aql_data_2\",\"aql_data_2\"]",
    ),
  )
  assert_true(
    actual.document.contains("\"node_properties\":{\"p\":\"number_sum\"}"),
  )
}
