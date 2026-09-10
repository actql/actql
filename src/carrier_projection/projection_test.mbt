///|
test "projection diagnostics retain the operation cursor and reject invalid limits" {
  let root = cursor("{\"events\":false}")
  let body = @decode.required(@decode.open_object(root).unwrap(), "events").unwrap()
  let rejected = @carrier_projection.check(
    Events,
    body,
    event(false, false),
    limits(),
  ).unwrap_err()
  assert_eq(rejected.path, [@source.Key("events")])
  assert_eq(rejected.span, @decode.cursor_span(body))
  let base = limits()
  let invalid : Array[@carrier_projection.Limits] = [
    { ..base, max_work: -1, },
    { ..base, max_nodes: -1, },
    { ..base, max_text_bytes: -1, },
    { ..base, max_depth: -1, },
  ]
  for cap in invalid {
    assert_eq(
      @carrier_projection.check(
        Events,
        cursor("true"),
        event(false, false),
        cap,
      ).unwrap_err().kind,
      InvalidLimits,
    )
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
fn limits() -> @carrier_projection.Limits {
  { max_work: 100, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, }
}

///|
fn event(open : Bool, untyped : Bool) -> @carrier.Carrier {
  @carrier.events(
    @carrier.rows(
      [
        (
          Unqualified("event_id"),
          Some(@contract.decimal_contract(38, 2, nullable=false).unwrap()),
        ),
        (
          Unqualified("clock"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("payload"),
          if untyped {
            None
          } else {
            Some(@contract.primitive(StringType, nullable=true))
          },
        ),
      ],
      field_set=if open { Open } else { Closed },
      max_fields=3,
      max_name_bytes=100,
    ).unwrap(),
    id=Unqualified("event_id"),
    time=Unqualified("clock"),
  ).unwrap()
}

///|
test "events preserves semantic fields and incomplete knowledge without physical aliases" {
  for open in [false, true] {
    for untyped in [false, true] {
      let input = event(open, untyped)
      let value = @carrier_projection.check(
        Events,
        cursor("true"),
        input,
        limits(),
      ).unwrap()
      let output = @carrier.relation_rows(@carrier_projection.output(value)).unwrap()
      assert_eq(@carrier.field_set(output), if open { Open } else { Closed })
      assert_eq(@carrier.field_count(output), 3)
      assert_eq(@carrier.complete_schema(output) is Some(_), !open && !untyped)
      guard @carrier.lookup(output, Unqualified("event_id")) is Present(id) else {
        fail("missing identity")
      }
      assert_true(
        @contract.type_equal(
          id.contract.unwrap(),
          @contract.decimal_contract(38, 2, nullable=false).unwrap(),
          10,
        ),
      )
      guard @carrier.lookup(output, Unqualified("payload")) is Present(payload) else {
        fail("missing payload")
      }
      assert_eq(payload.contract is None, untyped)
      assert_eq(@carrier.lookup(output, Unqualified("id")) is Unknown, open)
      let fields = @carrier.fields(output)
      fields.clear()
      assert_eq(@carrier.field_count(output), 3)
      assert_eq(@carrier.kind(@carrier_projection.input(value)), EventsKind)
    }
  }
}

///|
test "vectors preserves composite identity and dimensions without inventing id columns" {
  let records = @carrier.rows(
    [
      (
        Unqualified("tenant"),
        Some(@contract.primitive(StringType, nullable=false)),
      ),
      (
        Unqualified("item"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
      (
        Unqualified("embedding"),
        Some(@contract.vector_contract(12, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let input = @carrier.vectors(
    records,
    ids=[Unqualified("tenant"), Unqualified("item")],
    components=Unqualified("embedding"),
    max_identity_fields=2,
  ).unwrap()
  let value = @carrier_projection.check(
    Vectors,
    cursor("true"),
    input,
    limits(),
  ).unwrap()
  let output = @carrier.relation_rows(@carrier_projection.output(value)).unwrap()
  assert_eq(@carrier.field_count(output), 3)
  assert_true(@carrier.lookup(output, Unqualified("id")) is Absent)
  guard @carrier.lookup(output, Unqualified("embedding")) is Present(field) else {
    fail("embedding lost")
  }
  assert_true(
    @contract.type_equal(
      field.contract.unwrap(),
      @contract.vector_contract(12, nullable=false).unwrap(),
      10,
    ),
  )
}

///|
test "opaque carriers project unknown fields and reject other carrier kinds" {
  for operation in [@carrier_projection.Events, @carrier_projection.Vectors] {
    let expected = if operation == Events {
      @carrier.EventsKind
    } else {
      @carrier.VectorsKind
    }
    for kind in [@carrier.RelationKind, EventsKind, GraphKind, VectorsKind] {
      let result = @carrier_projection.check(
        operation,
        cursor("true"),
        @carrier.unknown_carrier(kind),
        limits(),
      )
      if kind == expected {
        let rows = @carrier.relation_rows(
          @carrier_projection.output(result.unwrap()),
        ).unwrap()
        assert_eq(@carrier.field_set(rows), Open)
        assert_true(@carrier.lookup(rows, Unqualified("x")) is Unknown)
        assert_true(@carrier.complete_schema(rows) is None)
      } else {
        assert_eq(result.unwrap_err().kind, WrongCarrier(kind))
      }
    }
  }
}

///|
test "projection requires true and accounts for exact inspection budgets" {
  let input = event(false, false)
  for body in ["false", "null", "{}", "[]", "1", "\"true\""] {
    assert_eq(
      @carrier_projection.check(Events, cursor(body), input, limits()).unwrap_err().kind,
      InvalidBody,
    )
  }
  let source = cursor("true")
  let checked = @carrier_projection.check(Events, source, input, limits()).unwrap()
  let used = @carrier_projection.usage(checked)
  assert_eq(used.nodes, 1)
  assert_eq(used.work, 4)
  assert_eq(used.text_bytes, 20)
  assert_true(@decode.boolean(@carrier_projection.source(checked)).unwrap())
  assert_eq(@carrier_projection.operation(checked), Events)
  assert_true(
    @carrier_projection.check(Events, source, input, {
      max_work: used.work,
      max_nodes: 1,
      max_text_bytes: used.text_bytes,
      max_depth: 0,
    })
    is Ok(_),
  )
  let budgets : Array[@carrier_projection.Limits] = [
    {
      max_work: used.work - 1,
      max_nodes: 1,
      max_text_bytes: used.text_bytes,
      max_depth: 0,
    },
    {
      max_work: used.work,
      max_nodes: 0,
      max_text_bytes: used.text_bytes,
      max_depth: 0,
    },
    {
      max_work: used.work,
      max_nodes: 1,
      max_text_bytes: used.text_bytes - 1,
      max_depth: 0,
    },
  ]
  for smaller in budgets {
    assert_eq(
      @carrier_projection.check(Events, source, input, smaller).unwrap_err().kind,
      BudgetExceeded,
    )
  }
}
