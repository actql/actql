///|
fn subgraph_test_identity() -> String {
  "{\"definition\":\"N\",\"domain\":\"sha256:" +
  "0".repeat(64) +
  "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
}

///|
fn subgraph_test_location(
  source : @decode.Cursor,
  path : Array[@source.PathSegment],
) -> @decode.Cursor {
  let mut current = source
  for segment in path {
    current = match segment {
      Index(index) => @decode.element_at(current, index).unwrap()
      Key(name) =>
        @decode.lookup(@decode.open_object(current).unwrap(), name).unwrap()
    }
  }
  current
}

///|
test "subgraph retains the admitted Graph and supports subsequent Graph consumers" {
  let graph = graph_graph_scope_input()
  let selected = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("element"),
          Some(@contract.primitive(JsonType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
  )
  for
    nodes in [
      "{\"ids\":[" + subgraph_test_identity() + "]}",
      "{\"from\":\"selected\",\"id\":\"element\"}",
    ] {
    let checked = @pipeline_typing.check_carriers(
      cursor(
        "[{\"from\":\"g\",\"subgraph\":{\"nodes\":" +
        nodes +
        ",\"edges\":\"active\"},\"as\":\"slice\"},{\"from\":\"slice\",\"normalize_graph\":true,\"as\":\"afterSubgraph\"}]",
      ),
      [("g", graph), ("selected", selected)],
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(checked, 0).unwrap()
    guard step.operation is Subgraph(selector~, checked=operation) else {
      fail("subgraph must retain the current checked operation")
    }
    assert_true(physical_equal(@graph.subgraph_output(operation), graph))
    assert_true(
      physical_equal(@pipeline_typing.output_carrier(checked).unwrap(), graph),
    )
    assert_eq(
      @pipeline_typing.step_at(checked, 1).unwrap().input,
      Some(Step(0)),
    )
    assert_eq(
      selector,
      if nodes.has_prefix("{\"from\"") {
        Some(Input(1))
      } else {
        None
      },
    )
    assert_eq(
      @pipeline_typing.input_occurrence_count(step),
      if selector is Some(_) {
        2
      } else {
        1
      },
    )
    assert_eq(
      @pipeline_typing.input_occurrence_at(step, 0).unwrap().target,
      Input(0),
    )
    if selector is Some(_) {
      let occurrence = @pipeline_typing.input_occurrence_at(step, 1).unwrap()
      assert_eq(occurrence.role, Right)
      assert_eq(occurrence.target, Input(1))
    }
    assert_true(@graph.subgraph_edges(operation) is Some(_))
    assert_eq(@graph.subgraph_pending_count(operation), 7)
  }
}

///|
test "subgraph Carrier diagnostics retain the exact current checker boundary" {
  let cases : Array[(@carrier.Carrier, @graph.IssueKind)] = [
    (@carrier.unknown_carrier(GraphKind), @graph.IncompleteGraph),
    (@carrier.unknown_carrier(RelationKind), @graph.WrongCarrier(RelationKind)),
    (@carrier.unknown_carrier(EventsKind), @graph.WrongCarrier(EventsKind)),
    (@carrier.unknown_carrier(VectorsKind), @graph.WrongCarrier(VectorsKind)),
  ]
  for (input, expected) in cases {
    let source = cursor(
      "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[" +
      subgraph_test_identity() +
      "]}}}]",
    )
    let issue = @pipeline_typing.check_carriers(
      source,
      [("g", input)],
      None,
      None,
      limits(),
    ).unwrap_err()
    let path : Array[@source.PathSegment] = [Index(0), Key("subgraph")]
    assert_eq(issue.kind, GraphMatch(@graph.Structure(expected)))
    assert_eq(issue.path, path)
    assert_eq(
      issue.span,
      @decode.cursor_span(subgraph_test_location(source, path)),
    )
    assert_true(issue.range is None)
  }
}

///|
test "subgraph retains exact malformed selector and unresolved reference diagnostics" {
  let cases : Array[
    (String, @pipeline_typing.IssueKind, Array[@source.PathSegment]),
  ] = [
    ("{}", InvalidBody, []),
    ("{\"nodes\":{\"ids\":[]},\"unknown\":true}", InvalidBody, []),
    ("{\"nodes\":{\"ids\":[],\"unknown\":true}}", InvalidBody, [Key("nodes")]),
    (
      "{\"nodes\":{\"ids\":[]}}",
      GraphMatch(@graph.Structure(@graph.InvalidBody)),
      [Key("nodes"), Key("ids")],
    ),
    (
      "{\"nodes\":{\"where\":\"true\"}}",
      GraphMatch(@graph.Structure(@graph.UnsupportedGraphOperation)),
      [Key("nodes"), Key("where")],
    ),
    (
      "{\"nodes\":{\"from\":\"missing\",\"id\":\"element\"}}",
      UnknownName("missing"),
      [Key("nodes"), Key("from")],
    ),
  ]
  for (body, expected, suffix) in cases {
    let source = cursor("[{\"from\":\"g\",\"subgraph\":" + body + "}]")
    let issue = @pipeline_typing.check_carriers(
      source,
      [("g", graph_input())],
      None,
      None,
      limits(),
    ).unwrap_err()
    let path : Array[@source.PathSegment] = [Index(0), Key("subgraph")] + suffix
    assert_eq(issue.kind, expected)
    assert_eq(issue.path, path)
    assert_eq(
      issue.span,
      @decode.cursor_span(subgraph_test_location(source, path)),
    )
    assert_true(issue.range is None)
  }
}
