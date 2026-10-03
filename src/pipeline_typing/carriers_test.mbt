///|
test "empty pipelines preserve optional current and opaque Carrier identity" {
  let kinds : Array[@carrier.Kind] = [
    RelationKind,
    GraphKind,
    EventsKind,
    VectorsKind,
  ]
  for kind in kinds {
    let value = @carrier.unknown_carrier(kind)
    let p = @pipeline_typing.check_carriers(
      cursor("[]"),
      [("data", value)],
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(@pipeline_typing.current(p), Some(Input(0)))
    assert_eq(@carrier.kind(@pipeline_typing.output_carrier(p).unwrap()), kind)
    assert_true(@pipeline_typing.output_schema(p) is None)
    assert_true(@pipeline_typing.carrier_at(p, Input(-1)) is None)
    assert_true(@pipeline_typing.carrier_at(p, Input(1)) is None)
    assert_true(@pipeline_typing.carrier_at(p, Step(0)) is None)
    let detached = @pipeline_typing.inputs(p)
    detached.clear()
    assert_eq(@pipeline_typing.inputs(p).length(), 1)
    let two = @pipeline_typing.check_carriers(
      cursor("[]"),
      [("a", value), ("b", value)],
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(@pipeline_typing.current(two), None)
    assert_true(@pipeline_typing.output_carrier(two) is None)
    assert_eq(@pipeline_typing.lookup(two, "b"), Some(Input(1)))
  }
}

///|
test "consumers distinguish Carrier mismatch from missing row type evidence" {
  let kinds : Array[@carrier.Kind] = [
    RelationKind,
    GraphKind,
    EventsKind,
    VectorsKind,
  ]
  for kind in kinds {
    let error = @pipeline_typing.check_carriers(
      cursor("[{\"select\":[\"id\"]}]"),
      [("data", @carrier.unknown_carrier(kind))],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(
      error.kind,
      if kind == RelationKind {
        IncompleteSchema
      } else {
        WrongCarrier(kind)
      },
    )
    assert_eq(error.path, [Index(0), Key("select")])
  }
  let error = @pipeline_typing.check_carriers(
    cursor("[{\"append\":{\"with\":\"other\"}}]"),
    [
      ("rows", @carrier.relation(@carrier.typed_rows(schema()))),
      ("other", @carrier.unknown_carrier(GraphKind)),
    ],
    None,
    Some(cursor("\"rows\"")),
    limits(),
  ).unwrap_err()
  assert_eq(error.kind, WrongCarrier(GraphKind))
  assert_eq(error.path, [Index(0), Key("append"), Key("with")])
}

///|
test "connection occurrences retain operand roles repeats and ownership" {
  let p = @pipeline_typing.check(
    cursor("[{\"append\":{\"with\":\"rows\"}},{\"drop\":[]}]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  let edges = @pipeline_typing.input_occurrences(step)
  assert_eq(edges.length(), 2)
  assert_eq(edges[0].role, Left)
  assert_eq(edges[1].role, Right)
  assert_eq(edges[0].target, Input(0))
  assert_eq(edges[1].target, Input(0))
  edges.clear()
  assert_eq(@pipeline_typing.input_occurrences(step).length(), 2)
  let next = @pipeline_typing.input_occurrences(
    @pipeline_typing.step_at(p, 1).unwrap(),
  )
  assert_eq(next.length(), 1)
  assert_eq(next[0].role, Primary)
  assert_eq(next[0].target, Step(0))
}

///|
test "event vector and partial field roles retain structure without inventing evidence" {
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.rows(
    [
      (Unqualified("id"), Some(number)),
      (Unqualified("time"), Some(number)),
      (
        Unqualified("vec"),
        Some(@contract.vector_contract(3.0, nullable=false).unwrap()),
      ),
      (Unqualified("payload"), None),
    ],
    field_set=Open,
    max_fields=4,
    max_name_bytes=16,
  ).unwrap()
  let events = @carrier.events(
    rows,
    id=Unqualified("id"),
    time=Unqualified("time"),
  ).unwrap()
  let vectors = @carrier.vectors(
    rows,
    ids=[Unqualified("id"), Unqualified("time")],
    components=Unqualified("vec"),
    max_identity_fields=2,
  ).unwrap()
  for value in [@carrier.relation(rows), events, vectors] {
    let inputs = [("data", value)]
    let p = @pipeline_typing.check_carriers(
      cursor("[]"),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(
      @carrier.kind(@pipeline_typing.output_carrier(p).unwrap()),
      @carrier.kind(value),
    )
    assert_true(@pipeline_typing.schema_at(p, Input(0)) is None)
    let used = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: used.work,
      max_text_bytes: used.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, {
        ..exact,
        max_work: used.work - 1,
      })
      is Err({ kind: BudgetExceeded, .. }),
    )
    assert_true(
      @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, {
        ..exact,
        max_text_bytes: used.text_bytes - 1,
      })
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "unused partially known and Graph contracts are preflighted within shared budgets" {
  let properties = @carrier.typed_rows(schema())
  let node = @carrier.property_node_definition(
    "N",
    [@contract.primitive(StringType, nullable=false)],
    properties,
    ["Node"],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [],
    max_definitions=1,
    max_contract_work=1000,
  ).unwrap()
  let inputs = [("rows", @carrier.relation(properties)), ("graph", graph)]
  let p = @pipeline_typing.check_carriers(
    cursor("[]"),
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  let used = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: used.work,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, exact)
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, {
      ..exact,
      max_work: used.work - 1,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    @pipeline_typing.check_carriers(cursor("[]"), inputs, None, None, {
      ..exact,
      max_text_bytes: used.text_bytes - 1,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
}
