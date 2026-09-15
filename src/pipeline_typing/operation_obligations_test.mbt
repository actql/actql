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
test "operation obligations retain selected shortest endpoint sides" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("node_id"),
    Unqualified("source_id"),
    Unqualified("target_id"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
  for
    (body, scopes) in [
      (
        "{\"subgraph\":{\"nodes\":{\"ids\":[1,1]}}}",
        [@pipeline_typing.Body, NodeSelector],
      ),
      (
        "{\"traverse\":{\"start\":{\"ids\":[1,1]},\"direction\":\"both\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"nodes\"}}",
        [Body, StartSelector],
      ),
      (
        "{\"shortest_path\":{\"source\":1,\"target\":2,\"direction\":\"both\",\"max_hops\":2}}",
        [Body],
      ),
      (
        "{\"shortest_path\":{\"source\":{\"ids\":[1]},\"target\":2,\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}",
        [Body, SourceSelector],
      ),
      (
        "{\"shortest_path\":{\"source\":1,\"target\":{\"ids\":[2]},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}",
        [Body, TargetSelector],
      ),
      (
        "{\"shortest_path\":{\"source\":{\"ids\":[1]},\"target\":{\"ids\":[2]},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}",
        [Body, SourceSelector, TargetSelector],
      ),
    ] {
    let p = @pipeline_typing.check_carriers(
      cursor("[" + body + "]"),
      [("g", graph)],
      None,
      None,
      limits(),
    ).unwrap()
    let op = @pipeline_typing.step_at(p, 0).unwrap().operation
    assert_obligation_groups(op, scopes)
    assert_true(
      @pipeline_typing.operation_obligations_selector(
        @pipeline_typing.operation_obligation_group_at(op, 0).unwrap(),
      )
      is None,
    )
    for i in 1..<scopes.length() {
      let g = @pipeline_typing.operation_obligation_group_at(op, i).unwrap()
      let selector = @pipeline_typing.operation_obligations_selector(g).unwrap()
      let expected = match op {
        Subgraph(checked=c, ..) => @graph.subgraph_nodes(c)
        Traverse(checked=c, ..) => @graph.traverse_start(c)
        Shortest(checked=c, ..) => {
          let side : @schema.Side = if scopes[i] == SourceSelector {
            Left
          } else {
            Right
          }
          guard @graph.shortest_endpoint(c, side) is Selected(s) else {
            abort("selected endpoint")
          }
          s
        }
        _ => abort("selector operation")
      }
      assert_true(physical_equal(selector, expected))
      assert_true(
        physical_equal(
          @pipeline_typing.operation_obligations_source(g),
          @graph.selector_source(expected),
        ),
      )
      let repeated = @pipeline_typing.operation_obligation_group_at(op, i).unwrap()
      assert_true(
        physical_equal(
          selector,
          @pipeline_typing.operation_obligations_selector(repeated).unwrap(),
        ),
      )
      assert_true(@pipeline_typing.operation_obligations_count(g) > 0)
      assert_true(
        @pipeline_typing.operation_obligations_at(g, 0)
        is Some(SelectorRequirement(_)),
      )
    }
  }
}

///|
test "union obligation groups retain every authored binary fold including repetition" {
  let a = structural_audit_producer(2)
  let p = @pipeline_typing.check_with_evidence(
    cursor("[{\"from\":\"a\",\"union_graphs\":{\"with\":[\"a\",\"a\",\"a\"]}}]"),
    [("a", @pipeline_typing.ProducedInput(a))],
    None,
    None,
    limits(),
  ).unwrap()
  let op = @pipeline_typing.step_at(p, 0).unwrap().operation
  assert_obligation_groups(op, [UnionFold(0), UnionFold(1), UnionFold(2)])
  guard op is GraphUnion(c) else { abort("union") }
  for i in 0..<3 {
    let g = @pipeline_typing.operation_obligation_group_at(op, i).unwrap()
    let expected = @graph.structural_pending(
      @graph.union_fold_at(c, i).unwrap(),
    )
    assert_eq(
      @pipeline_typing.operation_obligations_count(g),
      expected.length(),
    )
    for j in 0..<expected.length() {
      guard @pipeline_typing.operation_obligations_at(g, j)
        is Some(StructuralRequirement(actual)) else {
        abort("structural")
      }
      assert_eq(actual, expected[j])
      assert_true(
        physical_equal(
          @pipeline_typing.operation_obligation_source_at(g, j).unwrap(),
          @graph.structural_source(@graph.union_fold_at(c, i).unwrap()),
        ),
      )
    }
  }
}
