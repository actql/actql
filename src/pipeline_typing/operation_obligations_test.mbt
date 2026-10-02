///|
test "aggregate obligation locations retain call provenance rather than the operation body" {
  let p = match
    @pipeline_typing.check(
      cursor(
        "[{\"group\":{\"by\":[],\"aggregates\":{\"items\":{\"fn\":\"array_agg\",\"field\":\"amount\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":3}}}}]",
      ),
      [("rows", schema())],
      None,
      Some(cursor("\"rows\"")),
      limits(),
    ) {
    Ok(p) => p
    Err(issue) => fail(@debug.to_string(issue.kind))
  }
  let group = @pipeline_typing.operation_obligation_group_at(
    @pipeline_typing.step_at(p, 0).unwrap().operation,
    0,
  ).unwrap()
  assert_eq(
    @decode.cursor_path(@pipeline_typing.operation_obligations_source(group)),
    [@source.Index(0), @source.Key("group")],
  )
  let mut found = false
  for i in 0..<@pipeline_typing.operation_obligations_count(group) {
    if @pipeline_typing.operation_obligations_at(group, i)
      is Some(RelationRequirement(pending)) &&
      pending.kind == @relation.AggregateEnvelope {
      let source = @pipeline_typing.operation_obligation_source_at(group, i).unwrap()
      assert_true(physical_equal(source, pending.source))
      assert_eq(@decode.cursor_path(source), [
        @source.Index(0),
        @source.Key("group"),
        @source.Key("aggregates"),
        @source.Key("items"),
      ])
      found = true
    }
  }
  assert_true(found)
}

///|
fn assert_obligation_groups(
  operation : @pipeline_typing.CheckedOperation,
  scopes : Array[@pipeline_typing.OperationObligationScope],
) -> Unit raise {
  assert_eq(
    @pipeline_typing.operation_obligation_group_count(operation),
    scopes.length(),
  )
  for i in 0..<scopes.length() {
    let g = @pipeline_typing.operation_obligation_group_at(operation, i).unwrap()
    assert_eq(@pipeline_typing.operation_obligations_scope(g), scopes[i])
    let n = @pipeline_typing.operation_obligations_count(g)
    for j in 0..<n {
      assert_true(@pipeline_typing.operation_obligations_at(g, j) is Some(_))
      let source = @pipeline_typing.operation_obligation_source_at(g, j).unwrap()
      assert_true(
        physical_equal(
          source,
          @pipeline_typing.operation_obligation_source_at(g, j).unwrap(),
        ),
      )
    }
    for j in [-1, n, 2147483647] {
      assert_true(@pipeline_typing.operation_obligations_at(g, j) is None)
      assert_true(@pipeline_typing.operation_obligation_source_at(g, j) is None)
    }
  }
  for i in [-1, scopes.length(), 2147483647] {
    assert_true(
      @pipeline_typing.operation_obligation_group_at(operation, i) is None,
    )
  }
}

///|
test "current TRAIL obligations retain typed selector ownership and source provenance" {
  let graph = query_property_graph()
  let identity = "{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(@contract.primitive(JsonType, nullable=false)))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  )
  for
    start in [
      "{\"ids\":[" + identity + "," + identity + "]}",
      "{\"from\":\"selected\",\"id\":\"id\"}",
    ] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"from\":\"g\",\"traverse\":{\"start\":" +
        start +
        ",\"direction\":\"both\",\"min_hops\":0,\"max_hops\":2,\"path_mode\":\"trail\",\"emit\":\"paths\"}}]",
      ),
      [("g", graph), ("selected", rows)],
      None,
      None,
      limits(),
    ).unwrap()
    let op = @pipeline_typing.step_at(p, 0).unwrap().operation
    assert_obligation_groups(op, [Body, StartSelector])
    assert_true(
      @pipeline_typing.operation_obligations_selector(
        @pipeline_typing.operation_obligation_group_at(op, 0).unwrap(),
      )
      is None,
    )
    guard op is Traverse(checked~, ..) else { fail("current TRAIL") }
    let expected = @graph.traverse_start(checked)
    let group = @pipeline_typing.operation_obligation_group_at(op, 1).unwrap()
    let selector = @pipeline_typing.operation_obligations_selector(group).unwrap()
    assert_true(physical_equal(selector, expected))
    assert_true(
      physical_equal(
        @pipeline_typing.operation_obligations_source(group),
        @graph.selector_source(expected),
      ),
    )
    assert_true(
      physical_equal(
        selector,
        @pipeline_typing.operation_obligations_selector(
          @pipeline_typing.operation_obligation_group_at(op, 1).unwrap(),
        ).unwrap(),
      ),
    )
    assert_eq(@decode.cursor_path(@graph.selector_source(expected)), [
      Index(0),
      Key("traverse"),
      Key("start"),
    ])
    assert_true(@pipeline_typing.operation_obligations_count(group) > 0)
    assert_true(
      @pipeline_typing.operation_obligations_at(group, 0)
      is Some(SelectorRequirement(_)),
    )
    if @graph.selector_form(selector) is ExplicitIds {
      assert_eq(@graph.selector_id_count(selector), 2)
      let detached = @graph.selector_ids(selector)
      detached.clear()
      assert_eq(@graph.selector_id_count(selector), 2)
    } else {
      assert_true(
        @graph.selector_form(selector) is RelationIds(from="selected", ..),
      )
      assert_true(op is Traverse(selector=Some(Input(1)), ..))
    }
  }
}

///|
test "unsupported Graph consumers cannot issue legacy selector or structural fold obligations" {
  for
    (body, key) in [
      ("{\"subgraph\":{\"nodes\":{\"ids\":[]}}}", "subgraph"),
      (
        "{\"shortest_path\":{\"source\":{\"ids\":[]},\"target\":{\"ids\":[]},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}",
        "shortest_path",
      ),
      (
        "{\"from\":\"g\",\"union_graphs\":{\"with\":[\"g\",\"g\",\"g\"]}}", "union_graphs",
      ),
    ] {
    let issue = @pipeline_typing.check_carriers(
      cursor("[" + body + "]"),
      [("g", query_property_graph())],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, Graph(@graph.UnsupportedGraphOperation))
    assert_eq(issue.path, [Index(0), Key(key)])
  }
}
