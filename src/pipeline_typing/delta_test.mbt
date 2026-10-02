///|
/// Independent current Graph contract; no diff result or product-emitted bytes.
fn delta_contract() -> @graph_contract.CheckedContract raise {
  let body =
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":[]},"name":"N","properties":{}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
  let contract = @graph_contract.read_cursor(cursor(body), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  // Node crypto SHA-256 of the authored canonical body, independently computed.
  assert_eq(
    @graph_contract.cid(contract),
    "sha256:78b5e6a56288c04737f3a13a4b1ad9c653892cd22c060225f990e12406b45d1e",
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
