///|
test "unary Graph consumers distinguish supported contracts opaque evidence and wrong families" {
  let bodies = [
    ("normalize_graph", "true"),
    ("degree", "{\"direction\":\"in\"}"),
    ("degree", "{\"direction\":\"out\"}"),
    ("degree", "{\"direction\":\"both\"}"),
    ("components", "{\"kind\":\"weak\"}"),
    ("components", "{\"kind\":\"strong\"}"),
    ("graph_bounds", "{\"max_nodes\":0}"),
    ("graph_bounds", "{\"max_edges\":0}"),
    ("graph_bounds", "{\"max_degree\":0}"),
    ("graph_bounds", "{\"max_nodes\":0,\"max_edges\":0}"),
    ("graph_bounds", "{\"max_nodes\":0,\"max_degree\":0}"),
    ("graph_bounds", "{\"max_edges\":0,\"max_degree\":0}"),
    ("graph_bounds", "{\"max_nodes\":0,\"max_edges\":0,\"max_degree\":0}"),
  ]
  for (name, body) in bodies {
    let source = cursor("[{\"" + name + "\":" + body + "}]")
    let checked = @pipeline_typing.check_carriers(
      source,
      [("g", graph_input())],
      None,
      None,
      limits(),
    )
    if name == "degree" || name == "graph_bounds" {
      assert_true(checked is Ok(_))
    } else {
      let issue = checked.unwrap_err()
      assert_eq(issue.kind, Graph(@graph.UnsupportedGraphOperation))
      assert_eq(issue.path, [Index(0), Key(name)])
    }
    let missing = @pipeline_typing.check_carriers(
      source,
      [("g", @carrier.unknown_carrier(GraphKind))],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(missing.kind, Graph(@graph.IncompleteGraph))
    assert_eq(missing.path, [Index(0), Key(name)])
    let kinds : Array[@carrier.Kind] = [RelationKind, EventsKind, VectorsKind]
    for kind in kinds {
      let issue = @pipeline_typing.check_carriers(
        source,
        [("g", @carrier.unknown_carrier(kind))],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(issue.kind, Graph(@graph.WrongCarrier(kind)))
      assert_eq(issue.path, [Index(0), Key(name)])
    }
  }
}
