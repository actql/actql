///|
fn graph_input() -> @carrier.Carrier {
  @carrier.graph(
    @contract.decimal_contract(38, 9, nullable=false).unwrap(),
    @carrier.unknown_rows(),
    @carrier.unknown_rows(),
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
test "graph diff exposes typed delta rows and retains binary connections" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let g = @carrier.graph(
    @contract.primitive(StringType, nullable=false),
    empty,
    empty,
    labels=Some([]),
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"graph_diff\":{\"with\":\"b\"},\"from\":\"a\",\"as\":\"changes\"},{\"select\":[\"delta\"]}]",
    ),
    [("a", g), ("b", g)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.operation is GraphDiff(right=Input(1), ..))
  assert_eq(@pipeline_typing.input_occurrences(step).length(), 2)
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("delta"),
    ).unwrap().shape
    is Object(_),
  )
}

///|
test "graph equality resolves both inputs and feeds boolean relation consumers" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let g = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"graphs_equal\":{\"with\":\"b\"},\"from\":\"a\",\"as\":\"comparison\"},{\"filter\":\"equal\"}]",
    ),
    [("a", g), ("b", g)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.operation is GraphEquality(right=Input(1), ..))
  let edges = @pipeline_typing.input_occurrences(step)
  assert_eq(edges.length(), 2)
  assert_eq(edges[0].role, Left)
  assert_eq(edges[0].target, Input(0))
  assert_eq(edges[1].target, Input(1))
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{\"graphs_equal\":{\"with\":\"future\"},\"as\":\"future\"}]"),
      [("a", g)],
      None,
      None,
      limits(),
    )
    is Err({ kind: UnknownName("future"), .. }),
  )
}

///|
test "graph checking connects normalization components and relation projection" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"normalize_graph\":true,\"as\":\"normalized\"},{\"components\":{\"kind\":\"strong\"},\"as\":\"membership\"},{\"select\":[\"component_id\"]},{\"degree\":{\"direction\":\"both\"},\"from\":\"normalized\",\"as\":\"degrees\"}]",
    ),
    [("g", graph_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let graph = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(graph.output is GraphValue(_))
  assert_true(graph.operation is Graph(_))
  assert_eq(@pipeline_typing.input_occurrences(graph)[0].target, Input(0))
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(p, 3).unwrap())[0].target,
    Step(0),
  )
  assert_eq(@pipeline_typing.lookup(p, "membership"), Some(Step(1)))
  let schema = @pipeline_typing.output_schema(p).unwrap()
  assert_eq(@schema.field_count(schema), 2)
  assert_true(
    @contract.type_equal(
      @schema.lookup(schema, Unqualified("node")).unwrap(),
      @contract.decimal_contract(38, 9, nullable=false).unwrap(),
      10,
    ),
  )
  assert_true(@pipeline_typing.window_evidence(graph) is None)
}

///|
test "unknown graph identity remains unknown across fixed-role relation output" {
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"degree\":{\"direction\":\"out\"}}]"),
    [("g", @carrier.unknown_carrier(GraphKind))],
    None,
    None,
    limits(),
  ).unwrap()
  let output = @carrier.relation_rows(
    @pipeline_typing.output_carrier(p).unwrap(),
  ).unwrap()
  assert_eq(@carrier.field_count(output), 2)
  assert_true(@pipeline_typing.output_schema(p) is None)
  guard @carrier.lookup(output, Unqualified("node")) is Present(node) else {
    fail("node role missing")
  }
  assert_true(node.contract is None)
  let issue = @pipeline_typing.check_carriers(
    cursor("[{\"degree\":{\"direction\":\"out\"}},{\"select\":[\"node\"]}]"),
    [("g", @carrier.unknown_carrier(GraphKind))],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, IncompleteSchema)
}

///|
test "graph operations share pipeline budgets and preserve option diagnostics" {
  let body = cursor(
    "[{\"normalize_graph\":true},{\"degree\":{\"direction\":\"in\"}}]",
  )
  let p = @pipeline_typing.check_carriers(
    body,
    [("g", graph_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let used = @pipeline_typing.usage(p)
  let cap = limits()
  assert_true(
    @pipeline_typing.check_carriers(body, [("g", graph_input())], None, None, {
      ..cap,
      max_work: used.work,
      max_nodes: used.nodes,
      max_text_bytes: used.text_bytes,
    })
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(body, [("g", graph_input())], None, None, {
      ..cap,
      max_work: used.work - 1,
    })
    is Err(_),
  )
  let issue = @pipeline_typing.check_carriers(
    cursor("[{\"degree\":{\"direction\":\"up\"}}]"),
    [("g", graph_input())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.path, [
    @source.Index(0),
    @source.Key("degree"),
    @source.Key("direction"),
  ])
}
