///|
/// Independent current Graph contract; no diff result or product-emitted bytes.
fn delta_contract() -> @graph_contract.CheckedContract raise {
  let body =
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[],"identity_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":[]},"name":"N","properties":{}}],"value_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","version":"actql-graph-contract/0.1"}
  let contract = @graph_contract.read_cursor(cursor(body), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  // Node crypto SHA-256 of the authored canonical body, independently computed.
  assert_eq(
    @graph_contract.cid(contract),
    "sha256:183b5a03d53a1edef82907958e3a40620703dde16b01f617b82a7ecf4ba0f284",
  )
  contract
}

///|
fn delta_rows() -> @carrier.Carrier {
  @carrier.relation(
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
}

///|
test "Delta difference expectation survives projection and binds application operands" {
  let contract = delta_contract()
  let graph = @carrier.graph_carrier(@graph_contract.graph(contract))
  let pipeline = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"from":"base","graph_diff":{"with":"target"},"as":"changes"},
        #| {"select":[{"saved":"delta"}],"as":"retained"},
        #| {"from":"base","apply_graph_delta":{"with":"retained","field":"saved"}}]
      ),
    ),
    [("base", graph), ("target", graph)],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(pipeline, 0).unwrap()
  guard step.operation is @pipeline_typing.GraphDelta(right~, checked~) else {
    fail("missing difference owner")
  }
  assert_eq(right, @pipeline_typing.Input(1))
  assert_eq(@graph.delta_operation(checked), @graph.Difference)
  let expectation = @graph.delta_graph(checked)
  assert_eq(@graph_contract.cid(expectation), @graph_contract.cid(contract))
  for
    (target, field) in [
      (@pipeline_typing.Step(0), "delta"),
      (@pipeline_typing.Step(1), "saved"),
    ] {
    assert_true(
      physical_equal(
        @pipeline_typing.expected_delta_contract(
          pipeline,
          target,
          Unqualified(field),
        ).unwrap(),
        expectation,
      ),
    )
  }
  assert_true(
    @pipeline_typing.output_carrier(pipeline) is Some(@carrier.GraphValue(_)),
  )
  let applied = @pipeline_typing.step_at(pipeline, 2).unwrap()
  assert_eq(@pipeline_typing.input_occurrence_count(applied), 2)
  assert_true(
    @pipeline_typing.input_occurrence_at(applied, 0)
    is Some({ role: @pipeline_typing.Left, target: @pipeline_typing.Input(0), }),
  )
  assert_true(
    @pipeline_typing.input_occurrence_at(applied, 1)
    is Some({ role: @pipeline_typing.Right, target: @pipeline_typing.Step(1), }),
  )
  let slots = @pipeline_typing.collect_expression_slots(
    pipeline,
    max_work=100,
    max_slots=0,
  ).unwrap()
  assert_eq(@pipeline_typing.expression_slot_count(slots), 0)
}

///|
test "Delta application rejects an incompatible retained Graph expectation" {
  let expected = delta_contract()
  let issue = @pipeline_typing.check_carriers(
    cursor(
      "[{\"from\":\"base\",\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"}}]",
    ),
    [("base", graph_property_scope_input()), ("changes", delta_rows())],
    None,
    None,
    limits(),
    delta_contracts=[("changes", Unqualified("delta"), expected)],
  ).unwrap_err()
  assert_eq(issue.kind, Graph(@graph.DeltaContractMismatch))
}

///|
test "explicit current Graph expectations survive independent projection aliases" {
  let c = delta_contract()
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"select":[{"first":"delta"},{"second":"delta"}],"from":"d"},
        #| {"drop":["first"]},{"rename":{"second":"kept"},"as":"changes"}]
      ),
    ),
    [("d", delta_rows())],
    None,
    None,
    limits(),
    delta_contracts=[("d", Unqualified("delta"), c)],
  ).unwrap()
  for
    (target, field) in [
      (@pipeline_typing.Input(0), "delta"),
      (@pipeline_typing.Step(0), "first"),
      (@pipeline_typing.Step(0), "second"),
      (@pipeline_typing.Step(1), "second"),
      (@pipeline_typing.Step(2), "kept"),
    ] {
    assert_true(
      physical_equal(
        @pipeline_typing.expected_delta_contract(p, target, Unqualified(field)).unwrap(),
        c,
      ),
    )
  }
  assert_true(
    @pipeline_typing.expected_delta_contract(p, Step(1), Unqualified("first"))
    is None,
  )
  assert_true(
    @pipeline_typing.expected_delta_contract(p, Step(2), Unqualified("second"))
    is None,
  )
  guard @pipeline_typing.output_schema(p) is Some(rows) else {
    fail("Relation output")
  }
  assert_eq(@schema.field_count(rows), 1)
  assert_eq(@schema.field_at(rows, 0).unwrap().name, Unqualified("kept"))
}

///|
test "value preserving rows retain an explicit expectation but overwritten values do not" {
  let c = delta_contract()
  for
    source in [
      "[{\"sort\":[]}]", "[{\"filter\":\"TRUE\"}]", "[{\"derive\":{}}]",
    ] {
    let checked = @pipeline_typing.check_carriers(
      cursor(source),
      [("d", delta_rows())],
      None,
      None,
      limits(),
      delta_contracts=[("d", Unqualified("delta"), c)],
    ).unwrap()
    assert_true(
      physical_equal(
        @pipeline_typing.expected_delta_contract(
          checked,
          Step(0),
          Unqualified("delta"),
        ).unwrap(),
        c,
      ),
    )
  }
  let overwritten = @pipeline_typing.check_carriers(
    cursor("[{\"derive\":[{\"delta\":\"1\"}],\"as\":\"changed\"}]"),
    [("d", delta_rows())],
    None,
    None,
    limits(),
    delta_contracts=[("d", Unqualified("delta"), c)],
  ).unwrap()
  assert_true(
    @pipeline_typing.expected_delta_contract(
      overwritten,
      Step(0),
      Unqualified("delta"),
    )
    is None,
  )
  assert_true(
    physical_equal(
      @pipeline_typing.expected_delta_contract(
        overwritten,
        Input(0),
        Unqualified("delta"),
      ).unwrap(),
      c,
    ),
  )
}

///|
test "external current Graph expectations remain explicit and bounded rather than inferred from JSON" {
  let c = delta_contract()
  let source = cursor("[{\"filter\":\"TRUE\"}]")
  let inputs = [("d", delta_rows())]
  let unbound = @pipeline_typing.check_carriers(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.expected_delta_contract(
      unbound,
      Input(0),
      Unqualified("delta"),
    )
    is None,
  )
  assert_true(
    @pipeline_typing.expected_delta_contract(
      unbound,
      Step(0),
      Unqualified("delta"),
    )
    is None,
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
  for target in [@pipeline_typing.Input(0), @pipeline_typing.Step(0)] {
    assert_true(
      physical_equal(
        @pipeline_typing.expected_delta_contract(
          p,
          target,
          Unqualified("delta"),
        ).unwrap(),
        c,
      ),
    )
  }
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
  for
    bindings in [
      [binding, binding],
      [("unknown", Unqualified("delta"), c)],
      [("d", Unqualified("absent"), c)],
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        source,
        inputs,
        None,
        None,
        limits(),
        delta_contracts=bindings,
      )
      is Err({ kind: InvalidDeltaContractBinding, .. }),
    )
  }
  assert_true(
    @pipeline_typing.expected_delta_contract(p, Step(99), Unqualified("delta"))
    is None,
  )
}
