///|
test "shortest refusal preserves current Graph knowledge and Carrier kind diagnostics" {
  let source = cursor(
    "[{\"from\":\"g\",\"shortest_path\":{\"source\":1,\"target\":2,\"direction\":\"out\",\"max_hops\":1}}]",
  )
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
      source,
      [("g", input)],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, expected)
    assert_eq(issue.path, [Index(0), Key("shortest_path")])
  }
}

///|
test "shortest refusal retains closed-body and endpoint reference checking" {
  let cases : Array[(String, @pipeline_typing.IssueKind)] = [
    ("{\"source\":1}", InvalidBody),
    ("{\"source\":1,\"target\":2,\"unknown\":0}", InvalidBody),
    (
      "{\"source\":{\"from\":\"missing\",\"id\":\"identity\"},\"target\":2}",
      UnknownName("missing"),
    ),
    (
      "{\"source\":1,\"target\":{\"from\":\"missing\",\"id\":\"identity\"}}",
      UnknownName("missing"),
    ),
  ]
  for (body, expected) in cases {
    let issue = @pipeline_typing.check_carriers(
      cursor("[{\"from\":\"g\",\"shortest_path\":" + body + "}]"),
      [("g", graph_input())],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, expected)
  }
}
