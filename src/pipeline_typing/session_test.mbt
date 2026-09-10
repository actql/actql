///|
test "session preserves both carriers and connects generated labels to consumers" {
  let source = cursor(
    "[{\"session\":{\"by\":[],\"gap\":\"1s\"}},{\"events\":true},{\"select\":[\"session_id\",\"id\"]}]",
  )
  let p = @pipeline_typing.check_carriers(
    source,
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.step_at(p, 0).unwrap().output is EventValue(_))
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 0).unwrap())
    is None,
  )
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 2)
  guard event_input() is @carrier.EventValue(e) else { abort("events") }
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"session\":{\"id\":\"id\",\"time\":\"at\",\"by\":[],\"gap\":1}},{\"select\":[\"session_id\"]}]",
    ),
    [("input", @carrier.relation(e.records))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.step_at(p, 0).unwrap().output is Relation(_))
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
}

///|
test "session retains existing window roles and debits shared budgets" {
  let body = cursor(
    "[{\"window_events\":{\"kind\":\"fixed\",\"size\":10}},{\"session\":{\"by\":[\"id\"],\"gap\":1}},{\"events\":true},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
  )
  let p = @pipeline_typing.check_carriers(
    body,
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 1).unwrap())
    is Some(_),
  )
  let u = @pipeline_typing.usage(p)
  let cap = limits()
  let exact : @pipeline_typing.Limits = {
    ..cap,
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(
      body,
      [("input", event_input())],
      None,
      None,
      exact,
    )
    is Ok(_),
  )
  for
    caps in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        body,
        [("input", event_input())],
        None,
        None,
        caps,
      )
      is Err(_),
    )
  }
}
