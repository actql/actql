///|
test "graph union count propagation does not authenticate graph capacity claims" {
  for refs in ["\"g\"", "[\"g\"]", "[\"g\",\"g\"]"] {
    let occurrences = if refs == "[\"g\",\"g\"]" { 3L } else { 2L }
    let body = "[{\"values\":{\"schema\":{\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"src\":1,\"dst\":2}]},\"as\":\"seed\"},{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"union_graphs\":{\"with\":" +
      refs +
      "},\"as\":\"combined\"},{\"node_rows\":true},{\"from\":\"combined\",\"edge_rows\":true}]"
    let p = match
      @pipeline.check_carriers(cursor(body), [], None, None, {
        max_steps: 20,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 100000,
        max_tokens: 100000,
        max_depth: 100,
      }) {
      Ok(p) => p
      Err(e) => {
        debug_inspect(e.kind, content="no pipeline error")
        abort("pipeline")
      }
    }
    let counts = @pipeline.graph_count(p, Step(2)).unwrap()
    assert_eq(counts.nodes.unwrap().upper, occurrences * 2L)
    assert_eq(counts.edges.unwrap().upper, occurrences)
    assert_eq(@pipeline.row_count(p, Step(3)).unwrap().upper, occurrences * 2L)
    assert_eq(@pipeline.row_count(p, Step(4)).unwrap().upper, occurrences)
    for
      (index, law, unit, upper) in [
        (2, "actql.bound.graph-nodes", "nodes", occurrences * 2L),
        (2, "actql.bound.graph-edges", "edges", occurrences),
        (3, "actql.bound.graph-node-rows", "rows", occurrences * 2L),
        (4, "actql.bound.graph-edge-rows", "rows", occurrences),
      ] {
      for claimed in [0L, upper, upper + 1L] {
        let claim = proof(
          law,
          claimed,
          "{\"op\":\"source\"}",
          reference="checked-step:" + index.to_string(),
          unit~,
        )
        let result = @capacity_program_step.check(p, index, claim)
        assert_true(result is Err(InputCountMismatch))
      }
    }
  }
}
