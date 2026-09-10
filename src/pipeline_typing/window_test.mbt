///|
fn window_input() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("at"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("value"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
test "window pipeline retains bindings connections and value-preserving roles" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1},\"as\":\"windowed\"},{\"rename\":{\"window_start\":\"start\",\"window_end\":\"end\"}},{\"filter\":{\"literal\":true}}]",
    ),
    [("rows", window_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.lookup(p, "windowed"), Some(Step(0)))
  let first = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(first.operation is Window(_))
  assert_eq(@pipeline_typing.input_occurrences(first)[0].target, Input(0))
  let last = @pipeline_typing.step_at(p, 2).unwrap()
  assert_eq(
    @pipeline_typing.window_fields(
      @pipeline_typing.window_evidence(last).unwrap(),
    ),
    (@schema.Unqualified("start"), @schema.Unqualified("end")),
  )
}

///|
test "window roles disappear when boundaries are dropped or overwritten" {
  for
    next in [
      "{\"drop\":[\"window_end\"]}", "{\"derive\":[{\"window_start\":{\"literal\":1}}]}",
      "{\"select\":[\"at\",\"window_end\"]}",
    ] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1}}," +
        next +
        "]",
      ),
      [("rows", window_input())],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(
      @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 1).unwrap())
      is None,
    )
  }
}

///|
test "window spelling enforces its Carrier and cannot infer evidence from column names" {
  let event = @carrier.events(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(StringType, nullable=false)),
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
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"window_events\":{\"kind\":\"sliding\",\"size\":10,\"step\":3}}]",
    ),
    [("data", event)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @carrier.kind(@pipeline_typing.output_carrier(p).unwrap()),
    EventsKind,
  )
  for
    (body, input) in [
      (
        "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1}}]", event,
      ),
      ("[{\"window_events\":{\"kind\":\"fixed\",\"size\":1}}]", window_input()),
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor(body),
        [("data", input)],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
  let lookalike = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("window_start"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("window_end"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
  )
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"filter\":{\"literal\":true}}]"),
    [("rows", lookalike)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 0).unwrap())
    is None,
  )
}
