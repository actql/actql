///|
test "sessions preserve both input carriers and typed semantic roles" {
  guard events() is @carrier.EventValue(e) else { abort("events") }
  for relation in [false, true] {
    let input = if relation { @carrier.relation(e.records) } else { events() }
    let prefix = if relation { "\"id\":\"event\",\"time\":\"at\"," } else { "" }
    let source = cursor("{" + prefix + "\"by\":[],\"gap\":\"30m\"}")
    let checked = @event_typing.check_session(source, input, None, limits()).unwrap()
    assert_eq(
      @carrier.kind(@event_typing.output(checked)),
      @carrier.kind(input),
    )
    guard @event_typing.options(checked) is Session(s) else { abort("session") }
    assert_eq(@event_typing.session_identity(s), @row.Unqualified("event"))
    assert_true(@event_typing.session_keys(s).is_empty())
    assert_true(@event_typing.session_gap(s) is Literal(1800000L))
    let output = @event_typing.output(checked)
    let rows = match output {
      Relation(r) => r
      EventValue(e) => e.records
      _ => abort("carrier")
    }
    assert_eq(@carrier.field_count(rows), 6)
    assert_true(
      @carrier.lookup(rows, Unqualified("payload"))
      is Present({ contract: None, .. }),
    )
    assert_true(
      @carrier.lookup(rows, Unqualified("session_id"))
      is Present({ contract: Some({ shape: Text(_), nullable: false, }), .. }),
    )
    assert_true(
      indexed_obligation_copy(
        @event_typing.pending_validations(checked),
        @event_typing.pending_validation_count(checked),
        i => @event_typing.pending_validation_at(checked, i),
        (a, b) => a == b,
      ).contains(SessionIdentity),
    )
    let u = @event_typing.usage(checked)
    let cap = limits()
    let exact : @event_typing.Limits = {
      ..cap,
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @event_typing.check_session(source, input, None, exact) is Ok(_),
    )
    assert_true(
      @event_typing.check_session(source, input, None, {
        ..exact,
        max_nodes: u.nodes - 1,
      })
      is Err(_),
    )
  }
}

///|
test "session gap parameters defer binding and repeated keys retain occurrence order" {
  let ds = @parameter.read_declarations(
    Some(cursor("{\"gap\":{\"type\":\"number\",\"default\":-1}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @event_typing.check_session(
    cursor("{\"by\":[\"event\",\"event\"],\"gap\":{\"$param\":\"gap\"}}"),
    events(),
    Some(ds),
    limits(),
  ).unwrap()
  assert_true(
    indexed_obligation_copy(
      @event_typing.pending_validations(checked),
      @event_typing.pending_validation_count(checked),
      i => @event_typing.pending_validation_at(checked, i),
      (a, b) => a == b,
    ).contains(BindGap("gap")),
  )
  guard @event_typing.options(checked) is Session(s) else { abort("session") }
  let keys = @event_typing.session_keys(s)
  assert_eq(keys.length(), 2)
  keys.clear()
  assert_eq(@event_typing.session_keys(s).length(), 2)
  for
    body in [
      "{\"by\":[],\"gap\":0}", "{\"by\":[],\"gap\":\"1.5s\"}", "{\"by\":[\"payload\"],\"gap\":1}",
      "{\"by\":[],\"gap\":1,\"id\":\"event\"}",
    ] {
    assert_true(
      @event_typing.check_session(cursor(body), events(), None, limits())
      is Err(_),
    )
  }
  assert_true(
    @event_typing.check_session(
      cursor("{\"by\":[],\"gap\":1}"),
      events(collision="session_id"),
      None,
      limits(),
    )
    is Err({ kind: OutputCollision("session_id"), .. }),
  )
}
