///|
test "graph structural bounds propagate both extents through branches and matching" {
  for n in [0, 3] {
    for op in ["union_graphs", "graft_graph", "subtract_graphs"] {
      let source = cursor(
        "[" +
        graph_count_seed(n) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"" +
        op +
        "\":{\"with\":\"g\"},\"as\":\"combined\"},{\"subgraph\":{\"nodes\":{\"ids\":[1]}},\"as\":\"subset\"},{\"match_nodes\":{\"where\":\"true\",\"fields\":[\"node_id\"]}},{\"match_edges\":{\"where\":\"true\",\"fields\":[\"src\"]},\"from\":\"subset\"}]",
      )
      let p = graph_count_checked(
        @pipeline_typing.check_carriers(source, [], None, None, limits()),
      )
      let factor = if op == "subtract_graphs" { 1 } else { 2 }
      for i in [2, 3] {
        let bounds = @pipeline_typing.graph_count(p, Step(i)).unwrap()
        assert_eq(bounds.nodes.unwrap().upper, (factor * n * 2).to_int64())
        assert_eq(bounds.edges.unwrap().upper, (factor * n).to_int64())
      }
      assert_count(p, 4, (factor * n * 2).to_int64(), n == 0)
      assert_count(p, 5, (factor * n).to_int64(), n == 0)
      let u = @pipeline_typing.usage(p)
      let cap = {
        ..limits(),
        max_work: u.work,
        max_nodes: u.nodes,
        max_text_bytes: u.text_bytes,
      }
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, cap) is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, {
          ..cap,
          max_work: cap.max_work - 1,
        })
        is Err(_),
      )
    }
  }
}

///|
fn graph_count_seed(n : Int) -> String {
  let rows = Array::makei(n, i => {
    "{\"src\":" + i.to_string() + ",\"dst\":" + (i + 1).to_string() + "}"
  }).join(",")
  "{\"values\":{\"schema\":{\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
  rows +
  "]},\"as\":\"edges\"}"
}

///|
fn graph_count_checked(
  value : Result[@pipeline_typing.CheckedPipeline, @pipeline_typing.Issue],
) -> @pipeline_typing.CheckedPipeline raise {
  match value {
    Ok(v) => v
    Err(e) => fail(@debug.to_string(e.kind) + " " + @debug.to_string(e.path))
  }
}

///|
test "graph extents stay separate through normalization projection and node consumers" {
  for n in [0, 3] {
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(
        cursor(
          "[" +
          graph_count_seed(n) +
          ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"normalize_graph\":true,\"as\":\"normal\"},{\"node_rows\":true},{\"edge_rows\":true,\"from\":\"normal\"},{\"components\":{\"kind\":\"weak\"},\"from\":\"normal\"},{\"degree\":{\"direction\":\"both\"},\"from\":\"normal\"},{\"graphs_equal\":{\"with\":\"normal\"},\"from\":\"g\"}]",
        ),
        [],
        None,
        None,
        limits(),
      ),
    )
    for i in [1, 2] {
      assert_true(@pipeline_typing.row_count(p, Step(i)) is None)
      let graph = @pipeline_typing.graph_count(p, Step(i)).unwrap()
      assert_eq(graph.nodes.unwrap().upper, (2 * n).to_int64())
      assert_eq(graph.edges.unwrap().upper, n.to_int64())
      assert_eq(graph.nodes.unwrap().exact, n == 0)
      assert_eq(graph.edges.unwrap().exact, n == 0)
    }
    assert_count(p, 3, (2 * n).to_int64(), n == 0)
    assert_count(p, 4, n.to_int64(), n == 0)
    assert_count(p, 5, (2 * n).to_int64(), n == 0)
    assert_count(p, 6, (2 * n).to_int64(), n == 0)
    assert_count(p, 7, 1L, true)
    assert_true(@pipeline_typing.graph_count(p, Step(3)) is None)
    assert_true(@pipeline_typing.graph_count(p, Step(-1)) is None)
  }
}

///|
test "explicit empty node universe excludes all edges without importing edge count as node count" {
  for n in [0, 2] {
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(
        cursor(
          "[" +
          count_values(n, "nodes") +
          "," +
          graph_count_seed(3) +
          ",{\"graph\":{\"nodes\":{\"from\":\"nodes\",\"id\":\"id\"},\"edges\":{\"from\":\"edges\",\"source\":\"src\",\"target\":\"dst\"}},\"as\":\"g\"},{\"node_rows\":true},{\"edge_rows\":true,\"from\":\"g\"}]",
        ),
        [],
        None,
        None,
        limits(),
      ),
    )
    assert_count(p, 3, n.to_int64(), n == 0)
    assert_count(p, 4, if n == 0 { 0L } else { 3L }, n == 0)
    let u = @pipeline_typing.usage(p)
    assert_true(u.work > 0)
  }
}
