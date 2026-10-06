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
fn keyed_graph_count_prefix(nodes : Int, edges : Int) -> String {
  count_values(nodes, "nodes") +
  "," +
  graph_count_seed(edges) +
  ",{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"id\"]}],\"edges\":[{\"name\":\"E\",\"from\":\"edges\",\"key\":[\"src\"],\"source\":{\"definition\":\"N\",\"key\":[\"src\"]},\"target\":{\"definition\":\"N\",\"key\":[\"dst\"]}}]},\"as\":\"g\"}"
}

///|
test "explicit empty keyed node universe excludes edges without importing edge count as node count" {
  for n in [0, 2] {
    let source = cursor(
      "[" +
      keyed_graph_count_prefix(n, 3) +
      ",{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}},{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"element\"},\"fields\":[\"element\"]}}]",
    )
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(source, [], None, None, limits()),
    )
    let graph = @pipeline_typing.graph_count(p, Step(2)).unwrap()
    assert_true(@pipeline_typing.row_count(p, Step(2)) is None)
    assert_eq(graph.nodes.unwrap().upper, n.to_int64())
    assert_eq(graph.edges.unwrap().upper, if n == 0 { 0L } else { 3L })
    assert_count(p, 3, n.to_int64(), n == 0)
    assert_count(p, 4, if n == 0 { 0L } else { 3L }, n == 0)
    assert_true(@pipeline_typing.graph_count(p, Step(3)) is None)
    assert_true(@pipeline_typing.graph_count(p, Step(-1)) is None)
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, [], None, None, exact) is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, [], None, None, {
        ..exact,
        max_work: u.work - 1,
      })
      is Err(_),
    )
  }
}

///|
test "unsupported structural counts cannot propagate invented extents into current MATCH" {
  for name in ["graft_graph"] {
    let issue = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        keyed_graph_count_prefix(3, 3) +
        ",{\"" +
        name +
        "\":{\"with\":\"g\"},\"as\":\"combined\"},{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, Graph(@graph.UnsupportedGraphOperation))
    assert_eq(issue.path, [Index(3), Key(name)])
  }
}

///|
test "supported union structural counts include repeated occurrences without inventing exact extents" {
  for n in [0, 3] {
    let pipeline = graph_count_checked(
      @pipeline_typing.check_carriers(
        cursor(
          "[" +
          keyed_graph_count_prefix(n, 3) +
          ",{\"from\":\"g\",\"union_graphs\":{\"with\":\"g\"},\"as\":\"combined\"}" +
          ",{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}" +
          ",{\"from\":\"combined\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"element\"},\"fields\":[\"element\"]}}]",
        ),
        [],
        None,
        None,
        limits(),
      ),
    )
    let result = @pipeline_typing.graph_count(pipeline, Step(3)).unwrap()
    let nodes = 2L * n.to_int64()
    let edges = if n == 0 { 0L } else { 6L }
    assert_eq(result.nodes.unwrap().upper, nodes)
    assert_eq(result.edges.unwrap().upper, edges)
    assert_eq(result.nodes.unwrap().exact, n == 0)
    assert_eq(result.edges.unwrap().exact, n == 0)
    assert_true(@pipeline_typing.row_count(pipeline, Step(3)) is None)
    assert_count(pipeline, 4, nodes, n == 0)
    assert_count(pipeline, 5, edges, n == 0)
  }
}

///|
test "subtraction structural counts retain left upper bounds rather than assuming self annihilation" {
  for n in [0, 3] {
    let pipeline = graph_count_checked(
      @pipeline_typing.check_carriers(
        cursor(
          "[" +
          keyed_graph_count_prefix(n, 3) +
          ",{\"from\":\"g\",\"subtract_graphs\":{\"with\":\"g\"},\"as\":\"remaining\"}" +
          ",{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}" +
          ",{\"from\":\"remaining\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"element\"},\"fields\":[\"element\"]}}]",
        ),
        [],
        None,
        None,
        limits(),
      ),
    )
    // Shared records can be retained by explicit transformation maps. Count
    // propagation remains conservative and never borrows a union input sum.
    let result = @pipeline_typing.graph_count(pipeline, Step(3)).unwrap()
    let edges = if n == 0 { 0L } else { 3L }
    assert_eq(result.nodes.unwrap().upper, n.to_int64())
    assert_eq(result.edges.unwrap().upper, edges)
    assert_eq(result.nodes.unwrap().exact, n == 0)
    assert_eq(result.edges.unwrap().exact, n == 0)
    assert_true(@pipeline_typing.row_count(pipeline, Step(3)) is None)
    assert_count(pipeline, 4, n.to_int64(), n == 0)
    assert_count(pipeline, 5, edges, n == 0)
  }
}
