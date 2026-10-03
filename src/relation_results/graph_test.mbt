///|
test "unconnected structural Graph operations refuse before Result publication" {
  for
    (operation, expected) in [
      (
        "\"normalize_graph\":true",
        @pipeline.Graph(@graph.UnsupportedGraphOperation),
      ),
      (
        "\"components\":{\"kind\":\"weak\"}",
        @pipeline.Graph(@graph.UnsupportedGraphOperation),
      ),
      (
        "\"reach\":{\"start\":1,\"direction\":\"both\",\"max_depth\":2}",
        @pipeline.Graph(@graph.UnsupportedGraphOperation),
      ),
    ] {
    assert_eq(
      @pipeline.check_carriers(
        cursor("[{" + operation + ",\"as\":\"out\"}]"),
        [("g", property_query_graph())],
        None,
        None,
        ranking_limits(),
      ).unwrap_err().kind,
      expected,
    )
  }
}

///|
test "definition scoped MATCH feeds ordinary Relation steps and Result publication without tuple bridges" {
  for edges in [false, true] {
    let p = @pipeline.check_carriers(
      cursor(
        "[" +
        property_query_body(edges, "[\"element\",\"score\"]") +
        ",{\"select\":[{\"id\":\"element\"},\"score\"],\"as\":\"rows\"}]",
      ),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let result = @relation_results.check(
      p,
      cursor("{\"main\":{\"from\":\"rows\",\"fields\":[\"id\",\"score\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.count(result), 1)
    assert_eq(
      @relation_results.publication_strategy(resolve(result)),
      Inherited,
    )
    assert_true(
      @relation_results.check(
        p,
        cursor("{\"main\":{\"from\":\"g\",\"fields\":[\"id\"]}}"),
        limits(),
      )
      is Err({ kind: WrongCarrier(GraphKind), .. }),
    )
  }
  for operation in ["\"node_rows\":true", "\"edge_rows\":true"] {
    let rows = @pipeline.check_carriers(
      cursor("[{" + operation + ",\"as\":\"rows\"}]"),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let result = @relation_results.check(
      rows,
      cursor("{\"main\":{\"from\":\"rows\",\"fields\":[\"id\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.count(result), 1)
    assert_true(
      @pipeline.check_carriers(
        cursor("[{" + operation + "}]"),
        [("g", @carrier.unknown_carrier(GraphKind))],
        None,
        None,
        ranking_limits(),
      )
      is Err({ kind: Projection(IncompleteGraph), .. }),
    )
  }
}
