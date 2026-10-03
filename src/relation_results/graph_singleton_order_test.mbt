///|
test "unconnected Graph comparison cannot supply singleton publication evidence" {
  let graph = property_query_graph()
  for (operation, field) in [("graph_diff", "delta"), ("graphs_equal", "equal")] {
    for right in ["a", "b"] {
      assert_true(
        @pipeline.check_carriers(
          cursor(
            "[{\"" +
            operation +
            "\":{\"with\":\"" +
            right +
            "\"},\"from\":\"a\"},{\"select\":[\"" +
            field +
            "\"]},{\"filter\":{\"literal\":false}},{\"take\":1,\"as\":\"out\"}]",
          ),
          [("a", graph), ("b", graph)],
          None,
          None,
          ranking_limits(),
        )
        is Err({ kind: Graph(@graph.UnsupportedGraphOperation), .. }),
      )
    }
  }
}
