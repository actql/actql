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
    }
    for j in [-1, n, 2147483647] {
      assert_true(@pipeline_typing.operation_obligations_at(g, j) is None)
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
    for i in 1..<scopes.length() {
      let g = @pipeline_typing.operation_obligation_group_at(op, i).unwrap()
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
    }
  }
}
