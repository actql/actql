///|
fn delta_graph() -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
test "diff aliases survive independent projections and feed apply with binary roles" {
  let g = delta_graph()
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"graph_diff":{"with":"b"},"from":"a","as":"diff"},
        #| {"select":[{"first":"delta"},{"second":"delta"}]},
        #| {"drop":["first"]},{"rename":{"second":"kept"},"as":"changes"},
        #| {"apply_graph_delta":{"with":"changes","field":"kept"},"from":"a","as":"restored"},
        #| {"graphs_equal":{"with":"b"}}]
      ),
    ),
    [("a", g), ("b", g)],
    None,
    None,
    limits(),
  ).unwrap()
  let c = @pipeline_typing.expected_delta_contract(
    p,
    Step(3),
    Unqualified("kept"),
  ).unwrap()
  assert_true(
    @pipeline_typing.expected_delta_contract(p, Step(2), Unqualified("first"))
    is None,
  )
  let step = @pipeline_typing.step_at(p, 4).unwrap()
  guard step.operation is GraphApply(right=Step(3), checked~) else {
    fail("apply expected")
  }
  assert_eq(
    @graph_contract.cid(@graph.apply_graph_contract(checked)),
    @graph_contract.cid(c),
  )
  let edges = @pipeline_typing.input_occurrences(step)
  assert_true(edges[0] is { role: Left, target: Input(0), })
  assert_true(edges[1] is { role: Right, target: Step(3), })
  assert_true(@graph.apply_pending(checked).contains(MatchExactBaseIdentity))
  assert_true(@pipeline_typing.output_schema(p) is Some(_))
}

///|
test "value-preserving row operations keep expectations but overwriting derives lose them" {
  let g = delta_graph()
  for
    text in [
      (
        #|[{"graph_diff":{"with":"b"},"from":"a"},{"sort":[],"as":"d"},{"apply_graph_delta":{"with":"d","field":"delta"},"from":"a"}]
      ),
      (
        #|[{"graph_diff":{"with":"b"},"from":"a"},{"filter":"TRUE","as":"d"},{"apply_graph_delta":{"with":"d","field":"delta"},"from":"a"}]
      ),
      (
        #|[{"graph_diff":{"with":"b"},"from":"a"},{"derive":{},"as":"d"},{"apply_graph_delta":{"with":"d","field":"delta"},"from":"a"}]
      ),
    ] {
    let checked = @pipeline_typing.check_carriers(
      cursor(text),
      [("a", g), ("b", g)],
      None,
      None,
      limits(),
    )
    if checked is Err(e) {
      fail(text + " => " + @debug.to_string(e.kind))
    }
  }
  let result = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"graph_diff":{"with":"b"},"from":"a"},{"derive":[{"delta":"1"}],"as":"d"},{"apply_graph_delta":{"with":"d","field":"delta"},"from":"a"}]
      ),
    ),
    [("a", g), ("b", g)],
    None,
    None,
    limits(),
  )
  guard result is Err(e) else { fail("overwritten expectation survived") }
  assert_eq(e.kind, @pipeline_typing.MissingDeltaContract)
}

///|
test "external Delta contracts are explicit expectations not structural inference" {
  let g = delta_graph()
  let c = @graph_contract.admit(g, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let r = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("delta"),
          Some(@contract.primitive(JsonType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  )
  let source = cursor(
    "[{\"apply_graph_delta\":{\"with\":\"d\",\"field\":\"delta\"},\"from\":\"g\"}]",
  )
  let inputs = [("g", g), ("d", r)]
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, limits())
    is Err({ kind: MissingDeltaContract, .. }),
  )
  let binding = ("d", @schema.Unqualified("delta"), c)
  let p = @pipeline_typing.check_carriers(
    source,
    inputs,
    None,
    None,
    limits(),
    delta_contracts=[binding],
  ).unwrap()
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
    max_tokens: u.tokens,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, exact, delta_contracts=[
      binding,
    ])
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap, delta_contracts=[
        binding,
      ])
      is Err(_),
    )
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, limits(), delta_contracts=[
      binding, binding,
    ])
    is Err({ kind: InvalidDeltaContractBinding, .. }),
  )
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, limits(), delta_contracts=[
      ("unknown", Unqualified("delta"), c),
    ])
    is Err({ kind: InvalidDeltaContractBinding, .. }),
  )
  assert_true(
    @pipeline_typing.expected_delta_contract(p, Step(99), Unqualified("delta"))
    is None,
  )
}
