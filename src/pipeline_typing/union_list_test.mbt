///|
test "union list preserves unknown counts and scalar singleton equivalence" {
  let a = structural_audit_producer(2)
  let owner = @pipeline_typing.producer_pipeline(a)
  let raw = @pipeline_typing.step_at(owner, 1).unwrap().output
  let inputs = [
    ("a", @pipeline_typing.ProducedInput(a)),
    ("raw", @pipeline_typing.CarrierInput(raw)),
  ]
  for refs in ["[\"raw\",\"a\"]", "[\"a\",\"raw\"]"] {
    let p = @pipeline_typing.check_with_evidence(
      cursor(
        "[{\"from\":\"a\",\"union_graphs\":{\"with\":" +
        refs +
        "},\"as\":\"g\"},{\"node_rows\":true},{\"from\":\"g\",\"edge_rows\":true}]",
      ),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.row_count(p, Step(1)) is None)
    assert_true(@pipeline_typing.row_count(p, Step(2)) is None)
  }
  for refs in ["\"a\"", "[\"a\"]"] {
    let p = @pipeline_typing.check_with_evidence(
      cursor(
        "[{\"from\":\"a\",\"union_graphs\":{\"with\":" +
        refs +
        "}},{\"node_rows\":true}]",
      ),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, 1, 8L, false)
  }
}

///|
test "union list keeps one authored step ordered repeated edges and imported bounds" {
  let a = structural_audit_producer(2)
  let b = structural_audit_producer(3)
  let inputs = [
    ("a", @pipeline_typing.ProducedInput(a)),
    ("b", @pipeline_typing.ProducedInput(b)),
  ]
  let source = cursor(
    "[{\"from\":\"a\",\"union_graphs\":{\"with\":[\"b\",\"a\",\"b\"]},\"as\":\"joined\"},{\"node_rows\":true},{\"from\":\"joined\",\"edge_rows\":true}]",
  )
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.step_count(p), 3)
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  guard step.operation is GraphUnion(c) else { abort("union") }
  assert_eq(@graph.union_count(c), 3)
  assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
    Input(0),
    Input(1),
    Input(0),
    Input(1),
  ])
  assert_count(p, 1, 20L, false)
  assert_count(p, 2, 10L, false)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
      is Err(_),
    )
  }
  let e = @pipeline_typing.check_with_evidence(
    cursor("[{\"from\":\"a\",\"union_graphs\":{\"with\":[\"b\",\"missing\"]}}]"),
    inputs,
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(e.kind, UnknownName("missing"))
  assert_eq(e.path, [
    @source.Index(0),
    @source.Key("union_graphs"),
    @source.Key("with"),
    @source.Index(1),
  ])
  for op in ["graft_graph", "subtract_graphs"] {
    assert_true(
      @pipeline_typing.check_with_evidence(
        cursor("[{\"from\":\"a\",\"" + op + "\":{\"with\":[\"b\"]}}]"),
        inputs,
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}
