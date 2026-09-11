///|
fn delta_producer() -> @pipeline_typing.CheckedPipeline {
  let g = delta_graph()
  @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"graph_diff":{"with":"b"},"from":"a"},{"select":[{"first":"delta"},{"second":"delta"}]}]
      ),
    ),
    [("a", g), ("b", g)],
    None,
    None,
    limits(),
  ).unwrap()
}

///|
test "producer Delta contracts retain aliases and application obligations" {
  let producer = delta_producer()
  let input = @pipeline_typing.produced_input(producer, Step(1)).unwrap()
  let g = delta_graph()
  let inputs = [
    ("g", @pipeline_typing.CarrierInput(g)),
    ("d", @pipeline_typing.ProducedInput(input)),
  ]
  let source = cursor(
    (
      #|[{"drop":["first"],"from":"d","as":"changes"},{"apply_graph_delta":{"with":"changes","field":"second"},"from":"g"}]
    ),
  )
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  let expected = @pipeline_typing.expected_delta_contract(
    producer,
    Step(1),
    Unqualified("second"),
  ).unwrap()
  assert_true(
    physical_equal(
      @pipeline_typing.expected_delta_contract(
        p,
        Input(1),
        Unqualified("second"),
      ).unwrap(),
      expected,
    ),
  )
  assert_true(
    @pipeline_typing.expected_delta_contract(p, Step(0), Unqualified("first"))
    is None,
  )
  guard @pipeline_typing.step_at(p, 1).unwrap().operation
    is GraphApply(checked~, ..) else {
    fail("expected apply")
  }
  assert_eq(
    @graph_contract.cid(@graph.apply_graph_contract(checked)),
    @graph_contract.cid(expected),
  )
  assert_true(@graph.apply_pending(checked).contains(MatchExactBaseIdentity))
  assert_true(
    physical_equal(
      @pipeline_typing.producer_pipeline(
        @pipeline_typing.input_producer(p, 1).unwrap(),
      ),
      producer,
    ),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      source,
      [("g", g), ("d", @pipeline_typing.carrier_at(producer, Step(1)).unwrap())],
      None,
      None,
      limits(),
    )
    is Err({ kind: MissingDeltaContract, .. }),
  )
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
    max_tokens: u.tokens,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, {
      ..exact,
      max_work: u.work - 1,
    })
    is Err(_),
  )
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, {
      ..exact,
      max_text_bytes: u.text_bytes - 1,
    })
    is Err(_),
  )
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, limits(), delta_contracts=[
      ("d", Unqualified("second"), expected),
    ])
    is Err({ kind: InvalidDeltaContractBinding, .. }),
  )
}

///|
test "extending imported Delta expectations cannot mutate the original owner" {
  let seed = delta_producer()
  let producer = @pipeline_typing.check_with_evidence(
    cursor(
      (
        #|[{"derive":[{"second":"1"}]}]
      ),
    ),
    [
      (
        "d",
        @pipeline_typing.ProducedInput(
          @pipeline_typing.produced_input(seed, Step(1)).unwrap(),
        ),
      ),
    ],
    None,
    None,
    limits(),
  ).unwrap()
  let input = @pipeline_typing.produced_input(producer, Step(0)).unwrap()
  let contract = @pipeline_typing.expected_delta_contract(
    producer,
    Step(0),
    Unqualified("first"),
  ).unwrap()
  assert_true(
    @pipeline_typing.expected_delta_contract(
      producer,
      Step(0),
      Unqualified("second"),
    )
    is None,
  )
  let extended = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [("d", @pipeline_typing.ProducedInput(input))],
    None,
    None,
    limits(),
    delta_contracts=[("d", Unqualified("second"), contract)],
  ).unwrap()
  assert_true(
    @pipeline_typing.expected_delta_contract(
      extended,
      Input(0),
      Unqualified("second"),
    )
    is Some(_),
  )
  let untouched = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [("d", @pipeline_typing.ProducedInput(input))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.expected_delta_contract(
      untouched,
      Input(0),
      Unqualified("second"),
    )
    is None,
  )
  assert_true(
    @pipeline_typing.expected_delta_contract(
      producer,
      Step(0),
      Unqualified("second"),
    )
    is None,
  )
}

///|
test "Delta contract forwarding does not recursively traverse producer ancestry" {
  let producer = delta_producer()
  let mut input = @pipeline_typing.produced_input(producer, Step(1)).unwrap()
  let contract = @pipeline_typing.expected_delta_contract(
    producer,
    Step(1),
    Unqualified("first"),
  ).unwrap()
  for _ in 0..<2000 {
    let p = @pipeline_typing.check_with_evidence(
      cursor("[]"),
      [("d", @pipeline_typing.ProducedInput(input))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(
      physical_equal(
        @pipeline_typing.expected_delta_contract(
          p,
          Input(0),
          Unqualified("first"),
        ).unwrap(),
        contract,
      ),
    )
    input = @pipeline_typing.produced_input(p, Input(0)).unwrap()
  }
}
