///|
test "Graph count propagation does not authenticate capacity claims" {
  let body = keyed_repeated_measure_steps()
    .strip_suffix("]")
    .unwrap()
    .to_owned() +
    "," +
    keyed_measure_match("nodes") +
    ",{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}]"
  let p = graph_measure_pipeline(body)
  let counts = @pipeline.graph_count(p, Step(1)).unwrap()
  // One node and three independently keyed edge definitions each read one row.
  // E-only MATCH keeps the conservative whole-Graph edge upper bound, not an
  // assertion that all three definitions are selected or actually emitted.
  assert_eq(counts.nodes.unwrap().upper, 1L)
  assert_eq(counts.edges.unwrap().upper, 3L)
  assert_eq(@pipeline.row_count(p, Step(2)).unwrap().upper, 1L)
  assert_eq(@pipeline.row_count(p, Step(3)).unwrap().upper, 3L)
  for
    (index, law, unit, upper) in [
      (1, "actql.bound.graph-construction-nodes", "nodes", 1L),
      (1, "actql.bound.graph-construction-edges", "edges", 3L),
      (2, "actql.bound.match-nodes", "rows", 1L),
      (3, "actql.bound.match-edges", "rows", 3L),
    ] {
    for claimed in [0L, upper, upper + 1L] {
      let claim = proof(
        law,
        claimed,
        "{\"op\":\"source\"}",
        reference="checked-step:" + index.to_string(),
        unit~,
      )
      assert_true(
        @capacity_program_step.check(p, index, claim) is Err(InputCountMismatch),
      )
    }
  }
}
