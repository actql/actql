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
test "reach preserves semantic aliases through pipeline Relation consumers" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let number = @contract.primitive(NumberType, nullable=false)
  let names = @carrier.graph_row_names(
    Unqualified("customer"),
    Unqualified("source"),
    Unqualified("target"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let g = @carrier.graph(
    number,
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
  let body = cursor(
    "[{\"reach\":{\"start\":2,\"direction\":\"out\",\"max_depth\":3}},{\"select\":[\"customer\",\"depth\"]}]",
  )
  let p = @pipeline_typing.check_carriers(
    body,
    [("g", g)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.operation is Reach(_))
  assert_eq(@pipeline_typing.input_occurrences(step).length(), 1)
  assert_eq(@schema.field_count(@pipeline_typing.step_schema(step).unwrap()), 4)
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("customer"),
    ).unwrap().shape
    is Number,
  )
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(body, [("g", g)], None, None, exact)
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(body, [("g", g)], None, None, {
      ..exact,
      max_work: u.work - 1,
    })
    is Err(_),
  )
}

///|
test "subgraph resolves selector Relation edges and preserves graph contracts" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let number = @contract.primitive(NumberType, nullable=false)
  let g = @carrier.graph(
    number,
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let relation = @carrier.relation(
    @carrier.rows(
      [(Unqualified("chosen"), Some(number))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=6,
    ).unwrap(),
  )
  let body = cursor(
    "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"from\":\"r\",\"id\":\"chosen\"}},\"as\":\"subset\"},{\"node_rows\":true},{\"select\":[\"id\"]}]",
  )
  let p = @pipeline_typing.check_carriers(
    body,
    [("g", g), ("r", relation)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.operation is Subgraph(selector=Some(Input(1)), ..))
  let edges = @pipeline_typing.input_occurrences(step)
  assert_eq(edges.length(), 2)
  assert_eq(edges[0].target, Input(0))
  assert_eq(edges[1].target, Input(1))
  assert_eq(edges[1].role, Right)
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("id"),
    ).unwrap().shape
    is Number,
  )
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("g", g), ("r", relation)],
      None,
      None,
      exact,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("g", g), ("r", relation)],
      None,
      None,
      { ..exact, max_work: u.work - 1, },
    )
    is Err(_),
  )
  let c = @pipeline_typing.check_carriers(
    cursor("[{\"subgraph\":{\"nodes\":{\"ids\":[2]}}}]"),
    [("g", g)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(c, 0).unwrap()).length(),
    1,
  )
  assert_true(
    @pipeline_typing.check_carriers(
      cursor(
        "[{\"subgraph\":{\"nodes\":{\"from\":\"future\",\"id\":\"chosen\"}},\"as\":\"future\"}]",
      ),
      [("g", g)],
      None,
      None,
      limits(),
    )
    is Err({ kind: UnknownName("future"), .. }),
  )
}

///|
test "graph property matches connect relation consumers and preserve predicate ranges" {
  let boolean = @contract.primitive(BooleanType, nullable=true)
  let props = @carrier.rows(
    [(Unqualified("active"), Some(boolean))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("node_id"),
    Unqualified("source_id"),
    Unqualified("target_id"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let g = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    props,
    props,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
  for (op, field) in [("match_nodes", "node_id"), ("match_edges", "source_id")] {
    let body = cursor(
      "[{\"" +
      op +
      "\":{\"where\":\"active\",\"fields\":[\"" +
      field +
      "\",\"active\"]},\"as\":\"matched\"},{\"filter\":\"active\"},{\"select\":[\"" +
      field +
      "\"]}]",
    )
    let p = @pipeline_typing.check_carriers(
      body,
      [("g", g)],
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(p, 0).unwrap()
    assert_true(step.operation is GraphMatch(_))
    let edges = @pipeline_typing.input_occurrences(step)
    assert_eq(edges.length(), 1)
    assert_eq(edges[0].target, Input(0))
    assert_true(
      @schema.lookup(
        @pipeline_typing.output_schema(p).unwrap(),
        Unqualified(field),
      ).unwrap().shape
      is Number,
    )
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
      max_tokens: u.tokens,
    }
    assert_true(
      @pipeline_typing.check_carriers(body, [("g", g)], None, None, exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
        { ..exact, max_tokens: u.tokens - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_carriers(body, [("g", g)], None, None, cap)
        is Err(_),
      )
    }
  }
  let e = @pipeline_typing.check_carriers(
    cursor(
      "[{\"match_nodes\":{\"where\":\"active AND missing\",\"fields\":[\"node_id\"]}}]",
    ),
    [("g", g)],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_true(e.kind is GraphMatch(UnknownField("missing")))
  assert_eq(e.path, [
    @source.Index(0),
    @source.Key("match_nodes"),
    @source.Key("where"),
  ])
  assert_true(e.range is Some(_))
}

///|
test "structural graph composition retains repeated operands and feeds row consumers" {
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
  for name in ["graft_graph", "union_graphs", "subtract_graphs"] {
    let body = cursor(
      "[{\"" +
      name +
      "\":{\"with\":\"g\"},\"as\":\"composed\"},{\"node_rows\":true},{\"select\":[\"id\"]}]",
    )
    let p = @pipeline_typing.check_carriers(
      body,
      [("g", g)],
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(p, 0).unwrap()
    assert_true(step.operation is GraphStructural(right=Input(0), ..))
    let edges = @pipeline_typing.input_occurrences(step)
    assert_eq(edges.length(), 2)
    assert_eq(edges[0].role, Left)
    assert_eq(edges[1].role, Right)
    assert_eq(edges[0].target, Input(0))
    assert_eq(edges[1].target, Input(0))
    assert_true(
      @schema.lookup(
        @pipeline_typing.output_schema(p).unwrap(),
        Unqualified("id"),
      ).unwrap().shape
      is Number,
    )
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(body, [("g", g)], None, None, exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_carriers(body, [("g", g)], None, None, cap)
        is Err(_),
      )
    }
  }
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
