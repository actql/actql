///|
fn ordered_graph_source(operation : String) -> String {
  "[{\"values\":{\"schema\":{\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"src\":1,\"dst\":2} ]},\"as\":\"edges\"},{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{" +
  operation +
  "}]"
}

///|
test "ordered graph queries retain their origin through take and nonorderable Result projection" {
  for
    (operation, field) in [
      (
        "\"match_nodes\":{\"where\":\"true\",\"fields\":[\"node_id\"]}", "node_id",
      ),
      ("\"match_edges\":{\"where\":\"true\",\"fields\":[\"src\"]}", "src"),
      (
        "\"reach\":{\"start\":1,\"direction\":\"out\",\"max_depth\":2}", "node_id",
      ),
      (
        "\"traverse\":{\"start\":{\"ids\":[1]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"nodes\"}",
        "node_id",
      ),
      (
        "\"traverse\":{\"start\":{\"ids\":[1]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"paths\"}",
        "edge_ids",
      ),
      (
        "\"shortest_path\":{\"source\":1,\"target\":2,\"direction\":\"out\",\"max_hops\":2}",
        "node_ids",
      ),
      ("\"components\":{\"kind\":\"weak\"}", "component_id"),
      ("\"components\":{\"kind\":\"strong\"}", "component_id"),
    ] {
    let source = ordered_graph_source(
      operation + "},{\"take\":1,\"as\":\"query\"",
    )
    let p = @pipeline.check_carriers(
      cursor(source),
      [],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(p, Step(1)) is None)
    let order = @pipeline.logical_order(p, Step(2)).unwrap()
    assert_eq(@pipeline.order_origin(order), Step(2))
    assert_eq(
      @pipeline.order_origin(@pipeline.take_order(p, 3).unwrap()),
      Step(2),
    )
    let results = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"query\",\"fields\":[\"" + field + "\"]}}"),
      limits(),
    ).unwrap()
    let published = resolve(results)
    assert_eq(@relation_results.publication_strategy(published), Inherited)
    assert_eq(
      @pipeline.order_origin(
        @relation_results.publication_inherited_order(published).unwrap(),
      ),
      Step(2),
    )
    assert_eq(@relation_results.publication_term_count(published), 0)
    // Same shape without the checked query producer has no inherited order.
    let plain = @pipeline.check_carriers(
      cursor("[]"),
      [("query", @pipeline.output_carrier(p).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(plain, Input(0)) is None)
  }
}

///|
test "graph row projection alone does not claim canonical logical order" {
  for
    operation in [
      "\"node_rows\":true", "\"edge_rows\":true", "\"degree\":{\"direction\":\"out\"}",
    ] {
    let p = @pipeline.check_carriers(
      cursor(ordered_graph_source(operation)),
      [],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(p, Step(2)) is None)
  }
}
