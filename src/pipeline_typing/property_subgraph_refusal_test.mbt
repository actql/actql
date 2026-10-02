///|
test "subgraph refusal retains current Graph and Carrier diagnostics without a checked execution branch" {
  let cases : Array[(@carrier.Carrier, @pipeline_typing.IssueKind)] = [
    (graph_input(), Graph(@graph.UnsupportedGraphOperation)),
    (@carrier.unknown_carrier(GraphKind), Graph(@graph.IncompleteGraph)),
    (
      @carrier.unknown_carrier(RelationKind),
      Graph(@graph.WrongCarrier(RelationKind)),
    ),
    (
      @carrier.unknown_carrier(EventsKind),
      Graph(@graph.WrongCarrier(EventsKind)),
    ),
    (
      @carrier.unknown_carrier(VectorsKind),
      Graph(@graph.WrongCarrier(VectorsKind)),
    ),
  ]
  for (input, expected) in cases {
    let issue = @pipeline_typing.check_carriers(
      cursor("[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[]}}}]"),
      [("g", input)],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, expected)
    assert_eq(issue.path, [Index(0), Key("subgraph")])
  }
}

///|
test "subgraph refusal retains closed body selector and resolved reference boundaries" {
  let cases : Array[(String, @pipeline_typing.IssueKind)] = [
    ("{}", InvalidBody),
    ("{\"nodes\":{\"ids\":[]},\"unknown\":true}", InvalidBody),
    ("{\"nodes\":{\"ids\":[],\"unknown\":true}}", InvalidBody),
    (
      "{\"nodes\":{\"from\":\"missing\",\"id\":\"element\"}}",
      UnknownName("missing"),
    ),
  ]
  for (body, expected) in cases {
    let issue = @pipeline_typing.check_carriers(
      cursor("[{\"from\":\"g\",\"subgraph\":" + body + "}]"),
      [("g", graph_input())],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, expected)
  }
}
