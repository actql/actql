///|
test "vector projection feeds typed relational consumers without synthesizing fields" {
  let vector = @carrier.vectors(
    @carrier.rows(
      [
        (
          Unqualified("item"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("embedding"),
          Some(@contract.vector_contract(3, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
    ids=[Unqualified("item")],
    components=Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"vectors\":true,\"as\":\"rows\"},{\"select\":[\"item\"]}]"),
    [("input", vector)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(p, 0).unwrap())[0].target,
    Input(0),
  )
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("item"),
    ).unwrap().shape
    is Number,
  )
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 0).unwrap())
    is None,
  )
}

///|
fn event_input() -> @carrier.Carrier {
  @carrier.events(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("at"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
    id=Unqualified("id"),
    time=Unqualified("at"),
  ).unwrap()
}

///|
test "event projection connects window roles to relational grouping and branching" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"window_events\":{\"kind\":\"fixed\",\"size\":10},\"as\":\"windowed\"},{\"events\":true,\"as\":\"rows\"},{\"window_group\":{\"by\":[],\"aggregates\":{}}},{\"events\":true,\"from\":\"windowed\",\"as\":\"again\"}]",
    ),
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.lookup(p, "rows"), Some(Step(1)))
  let projected = @pipeline_typing.step_at(p, 1).unwrap()
  assert_eq(@pipeline_typing.input_occurrences(projected)[0].target, Step(0))
  assert_true(projected.operation is Projection(_))
  assert_eq(
    @pipeline_typing.window_fields(
      @pipeline_typing.window_evidence(projected).unwrap(),
    ),
    (Unqualified("window_start_ms"), Unqualified("window_end_ms")),
  )
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 2).unwrap())
    is Some(_),
  )
  assert_eq(@pipeline_typing.current(p), Some(Step(3)))
  assert_eq(
    @pipeline_typing.input_occurrences(@pipeline_typing.step_at(p, 3).unwrap())[0].target,
    Step(0),
  )
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 4)
}

///|
test "projection preserves opaque knowledge and uses shared cumulative budgets" {
  for
    (key, kind) in [
      ("events", @carrier.EventsKind),
      ("vectors", @carrier.VectorsKind),
    ] {
    let p = @pipeline_typing.check_carriers(
      cursor("[{\"" + key + "\":true}]"),
      [("input", @carrier.unknown_carrier(kind))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.output_schema(p) is None)
    assert_true(
      @pipeline_typing.output_carrier(p) is Some(@carrier.Relation(_)),
    )
    let issue = @pipeline_typing.check_carriers(
      cursor("[{\"" + key + "\":true},{\"select\":[\"id\"]}]"),
      [("input", @carrier.unknown_carrier(kind))],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, IncompleteSchema)
  }
  let body = cursor("[{\"events\":true},{\"events\":true,\"from\":\"input\"}]")
  let p = @pipeline_typing.check_carriers(
    body,
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let used = @pipeline_typing.usage(p)
  let cap = limits()
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("input", event_input())],
      None,
      None,
      {
        ..cap,
        max_work: used.work,
        max_nodes: used.nodes,
        max_text_bytes: used.text_bytes,
      },
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("input", event_input())],
      None,
      None,
      { ..cap, max_work: used.work - 1, },
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("input", event_input())],
      None,
      None,
      { ..cap, max_nodes: used.nodes - 1, },
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("input", event_input())],
      None,
      None,
      { ..cap, max_text_bytes: used.text_bytes - 1, },
    )
    is Err(_),
  )
}
