///|
fn graph_input() -> @carrier.Carrier {
  query_property_graph()
}

///|
fn graph_property_scope_input() -> @carrier.Carrier {
  let props = @carrier.rows(
    [
      (
        Unqualified("active"),
        Some(@contract.primitive(BooleanType, nullable=true)),
      ),
    ],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [@contract.primitive(NumberType, nullable=false)],
    props,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "E",
      [@contract.primitive(NumberType, nullable=false)],
      props,
      ["Link"],
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [edge],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
}

///|
test "TRAIL without predicates has no slots while MATCH keeps the common expression owner" {
  let graph = graph_property_scope_input()
  let relation = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(@contract.primitive(JsonType, nullable=false)))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  )
  for
    (body, expected_slots, expected_work) in [
      (
        "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"r\",\"id\":\"id\"},\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"Link\"]}],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]",
        0, 3,
      ),
      (
        "[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"where\":\"active\",\"fields\":[\"active\"]}}]",
        1, 2,
      ),
    ] {
    let pipeline = @pipeline_typing.check_carriers(
      cursor(body),
      [("g", graph), ("r", relation)],
      None,
      None,
      limits(),
    ).unwrap()
    let slots = collect_expression_slots(
      pipeline,
      max_work=expected_work,
      max_slots=expected_slots,
    ).unwrap()
    assert_true(physical_equal(expression_slots_pipeline(slots), pipeline))
    assert_eq(expression_slots_work(slots), expected_work)
    assert_eq(expression_slot_count(slots), expected_slots)
    assert_true(
      collect_expression_slots(
        pipeline,
        max_work=expected_work - 1,
        max_slots=expected_slots,
      )
      is Err(WorkLimit),
    )
    assert_true(expression_slot_at(slots, -1) is None)
    assert_true(expression_slot_at(slots, expected_slots) is None)
    if expected_slots == 1 {
      let slot = expression_slot_at(slots, 0).unwrap()
      assert_eq(slot.consumer, GraphMatchPredicate)
      assert_eq(slot.step, 0)
      assert_true(
        collect_expression_slots(pipeline, max_work=expected_work, max_slots=0)
        is Err(SlotLimit),
      )
    }
  }
}

///|
test "current TRAIL retains selector inputs and complete independent identity arrays through projection" {
  let g = graph_input()
  let r = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(@contract.primitive(JsonType, nullable=false)))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  )
  let source = cursor(
    "[{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"r\",\"id\":\"id\"},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"path_mode\":\"trail\",\"emit\":\"paths\"}},{\"select\":[\"start_id\",\"edge_ids\"]}]",
  )
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(
      source,
      [("g", g), ("r", r)],
      None,
      None,
      limits(),
    ),
  )
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  guard step.operation is Traverse(selector=Some(Input(1)), checked~) else {
    fail("current TRAIL")
  }
  assert_eq(@graph.traverse_property_path_mode(checked), Trail)
  assert_true(physical_equal(@graph.traverse_input(checked), g))
  let edges = @pipeline_typing.input_occurrences(step)
  assert_eq(edges.length(), 2)
  assert_eq(edges[0].target, Input(0))
  assert_eq(edges[1].target, Input(1))
  let schema = @pipeline_typing.output_schema(p).unwrap()
  let start = @schema.lookup(schema, Unqualified("start_id")).unwrap()
  assert_false(start.nullable)
  assert_true(start.shape is Json)
  let array = @schema.lookup(schema, Unqualified("edge_ids")).unwrap()
  assert_false(array.nullable)
  guard array.shape is @contract.Array(item, ..) else {
    fail("independent edge identity array")
  }
  assert_false(item.nullable)
  assert_true(item.shape is Json)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
    max_tokens: u.tokens,
  }
  assert_true(
    @pipeline_typing.check_carriers(
      source,
      [("g", g), ("r", r)],
      None,
      None,
      exact,
    )
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        source,
        [("g", g), ("r", r)],
        None,
        None,
        cap,
      )
      is Err(_),
    )
  }
}

///|
test "definition-scoped property MATCH connects Relation consumers and preserves predicate diagnostics" {
  let graph = graph_property_scope_input()
  for (op, definition) in [("match_nodes", "N"), ("match_edges", "E")] {
    let body = cursor(
      "[{\"" +
      op +
      "\":{\"definition\":\"" +
      definition +
      "\",\"bindings\":{\"identity\":\"element\"},\"where\":\"active\",\"fields\":[\"element\",\"active\"]},\"as\":\"matched\"},{\"filter\":\"active\"},{\"select\":[\"element\"]}]",
    )
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(
        body,
        [("g", graph)],
        None,
        None,
        limits(),
      ),
    )
    let step = @pipeline_typing.step_at(p, 0).unwrap()
    guard step.operation is GraphMatch(checked) else { fail("scoped MATCH") }
    assert_true(physical_equal(@graph.match_input(checked), graph))
    assert_eq(@graph.match_property_definition_name(checked), definition)
    let edges = @pipeline_typing.input_occurrences(step)
    assert_eq(edges.length(), 1)
    assert_eq(edges[0].target, Input(0))
    let element = @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("element"),
    ).unwrap()
    assert_false(element.nullable)
    assert_true(element.shape is Json)
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
      max_tokens: u.tokens,
    }
    assert_true(
      @pipeline_typing.check_carriers(body, [("g", graph)], None, None, exact)
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
        @pipeline_typing.check_carriers(body, [("g", graph)], None, None, cap)
        is Err(_),
      )
    }
    let issue = @pipeline_typing.check_carriers(
      cursor(
        "[{\"" +
        op +
        "\":{\"definition\":\"" +
        definition +
        "\",\"bindings\":{\"identity\":\"element\"},\"where\":\"active AND missing\",\"fields\":[\"element\"]}}]",
      ),
      [("g", graph)],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_true(issue.kind is GraphMatch(UnknownField("missing")))
    assert_eq(issue.path, [Index(0), Key(op), Key("where")])
    assert_true(issue.range is Some(_))
  }
}

///|
test "missing or wrong Graph evidence cannot fabricate current MATCH rows" {
  let body = cursor("[" + query_match_body(false, "[\"element\"]") + "]")
  let issue = @pipeline_typing.check_carriers(
    body,
    [("g", @carrier.unknown_carrier(GraphKind))],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(
    issue.kind,
    GraphMatch(@graph.Structure(@graph.WrongCarrier(GraphKind))),
  )
  assert_eq(issue.path, [Index(0), Key("match_nodes")])
  let kinds : Array[@carrier.Kind] = [RelationKind, EventsKind, VectorsKind]
  for kind in kinds {
    let issue = @pipeline_typing.check_carriers(
      body,
      [("g", @carrier.unknown_carrier(kind))],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(
      issue.kind,
      GraphMatch(@graph.Structure(@graph.WrongCarrier(kind))),
    )
    assert_eq(issue.path, [Index(0), Key("match_nodes")])
  }
}

///|
test "unsupported current Graph consumers cannot manufacture a legacy checked pipeline" {
  let identity = "{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
  for
    (name, body) in [
      ("normalize_graph", "true"),
      ("degree", "{\"direction\":\"both\"}"),
      ("components", "{\"kind\":\"strong\"}"),
      ("graph_bounds", "{\"max_nodes\":1}"),
      (
        "reach",
        "{\"start\":{\"ids\":[" +
        identity +
        "]},\"direction\":\"out\",\"max_depth\":1}",
      ),
      (
        "shortest_path",
        "{\"source\":{\"ids\":[" +
        identity +
        "]},\"target\":{\"ids\":[" +
        identity +
        "]},\"direction\":\"out\",\"max_hops\":1}",
      ),
      ("subgraph", "{\"nodes\":{\"where\":\"active\"},\"edges\":\"active\"}"),
      ("graphs_equal", "{\"with\":\"peer\"}"),
      ("graph_diff", "{\"with\":\"peer\"}"),
      ("graft_graph", "{\"with\":\"peer\"}"),
      ("subtract_graphs", "{\"with\":\"peer\"}"),
      ("union_graphs", "{\"with\":[\"peer\",\"g\",\"peer\"]}"),
      (
        "mean_graphs", "{\"with\":[\"peer\",\"g\"],\"weights\":[1,1],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}",
      ),
    ] {
    let issue = @pipeline_typing.check_carriers(
      cursor(
        "[{" +
        (if name == "mean_graphs" {
          "\"as\":\"mean\","
        } else {
          "\"from\":\"g\","
        }) +
        "\"" +
        name +
        "\":" +
        body +
        "}]",
      ),
      [
        ("g", graph_property_scope_input()),
        ("peer", graph_property_scope_input()),
      ],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_true(
      issue.kind is Graph(@graph.UnsupportedGraphOperation) ||
      issue.kind
      is GraphMatch(@graph.Structure(@graph.UnsupportedGraphOperation)),
    )
    assert_eq(issue.path, [Index(0), Key(name)])
  }
}

///|
test "unsupported mean generator keeps required alias and conflicting from diagnostics" {
  let body = "\"mean_graphs\":{\"with\":[\"g\",\"g\"],\"weights\":[1,0],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}"
  for
    (extra, expected) in [
      ("", @pipeline_typing.GeneratorRequiresAlias),
      (",\"as\":\"mean\",\"from\":\"g\"", GeneratorFrom),
    ] {
    let issue = @pipeline_typing.check_carriers(
      cursor("[{" + body + extra + "}]"),
      [("g", graph_input())],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, expected)
  }
}

///|
test "unsupported mean validates authored options without issuing Graph work" {
  let valid = "{\"with\":[\"g\",\"g\"],\"weights\":[1,0],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}"
  for
    (body, kind, path) in [
      (
        valid,
        @graph.UnsupportedGraphOperation,
        [@source.Index(0), @source.Key("mean_graphs")],
      ),
      (
        valid.replace(old="[1,0]", new="[0,0]"),
        @graph.InvalidWeight,
        [@source.Index(0), @source.Key("mean_graphs"), @source.Key("weights")],
      ),
      (
        valid.replace(old="\"nodes\":{}", new="\"nodes\":{\"score\":\"bogus\"}"),
        @graph.InvalidPropertyStrategy("bogus"),
        [
          @source.Index(0),
          @source.Key("mean_graphs"),
          @source.Key("properties"),
          @source.Key("nodes"),
          @source.Key("score"),
        ],
      ),
    ] {
    let issue = @pipeline_typing.check_carriers(
      cursor("[{\"as\":\"mean\",\"mean_graphs\":" + body + "}]"),
      [("g", graph_property_scope_input())],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, Graph(kind))
    assert_eq(issue.path, path)
  }
}

///|
test "current Graph refuses Delta application without issuing a tuple output or permission" {
  let graph = graph_property_scope_input()
  let contract = @graph_contract.admit(graph, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let issue = @pipeline_typing.check_carriers(
    cursor(
      "[{\"apply_graph_delta\":{\"with\":\"d\",\"field\":\"delta\"},\"from\":\"g\"}]",
    ),
    [("g", graph), ("d", delta_rows())],
    None,
    None,
    limits(),
    delta_contracts=[("d", Unqualified("delta"), contract)],
  ).unwrap_err()
  assert_eq(issue.kind, Graph(@graph.UnsupportedGraphOperation))
  assert_eq(issue.path, [Index(0), Key("apply_graph_delta")])
}
