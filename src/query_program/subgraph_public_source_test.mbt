///|
test "Subgraph task-bound example passes semantic checking before task admission" {
  let text =
    #|DATA n = SELECT 3 AS node_key, CAST(NULL AS FLOAT64) AS p UNION ALL SELECT 2 AS node_key, 20 AS p UNION ALL SELECT 1 AS node_key, 10 AS p; DATA e = SELECT 11 AS edge_key, 1 AS src_key, 2 AS dst_key, 20 AS w UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 2 AS dst_key, 10 AS w UNION ALL SELECT 12 AS edge_key, 2 AS src_key, 3 AS dst_key, 40 AS w UNION ALL SELECT 13 AS edge_key, 2 AS src_key, 2 AS dst_key, 30 AS w; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R PROPERTIES (w))); DATA selected = FROM g |> node_rows() |> WHERE node_key <= 2 |> SELECT id; FROM g |> subgraph(nodes: {from: selected, id: "id"}) |> node_rows() |> SELECT node_key, p |> ORDER BY node_key |> RESULT answer
  let program = compile_data_set(text)
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("No acquisition in authored source")
  }
}
