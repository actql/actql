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
test "window groups prepend boundaries once and preserve ordinary repeated keys" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}},{\"window_group\":{\"by\":[\"value\",\"window_start\",\"value\",\"window_end\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
    ),
    [("rows", window_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(p, 1).unwrap()
  match step.operation {
    WindowGroup(checked) => {
      let group = @relation.group(checked).unwrap()
      assert_eq(
        @relation.group_keys(group).map(k => @schema.reference_name(k.field)),
        ["window_start", "window_end", "value", "value"],
      )
      assert_eq(@relation.aggregate_count(group), 1)
    }
    _ => fail("expected window group")
  }
  assert_eq(
    @schema.fields(@pipeline_typing.output_schema(p).unwrap()).map(f => {
      @schema.reference_name(f.name)
    }),
    ["n", "value", "window_end", "window_start"],
  )
  assert_true(@pipeline_typing.window_evidence(step) is Some(_))
}

///|
test "window groups use transferred roles and permit empty ordinary grouping" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":3}},{\"rename\":{\"window_start\":\"begin\",\"window_end\":\"end\"}},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
    ),
    [("rows", window_input())],
    None,
    None,
    limits(),
  ).unwrap()
  match @pipeline_typing.step_at(p, 2).unwrap().operation {
    WindowGroup(checked) =>
      assert_eq(
        @relation.group_keys(@relation.group(checked).unwrap()).map(k => {
          @schema.reference_name(k.field)
        }),
        ["begin", "end"],
      )
    _ => fail("expected window group")
  }
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 2)
}

///|
test "window groups reject missing or invalidated evidence before aggregate checking" {
  for
    prefix in [
      "", "{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1}},{\"drop\":[\"window_end\"]},",
      "{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1}},{\"derive\":[{\"window_start\":{\"literal\":1}}]},",
    ] {
    let issue = @pipeline_typing.check_carriers(
      cursor("[" + prefix + "{\"window_group\":{\"by\":[],\"aggregates\":{}}}]"),
      [("rows", window_input())],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, MissingWindowEvidence)
  }
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
