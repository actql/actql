///|
test "event dedupe retains empty and repeated partitions without inventing order proof" {
  for by in ["[]", "[\"event\",\"event\"]"] {
    let checked = @event_typing.check_dedupe(
      cursor("{\"by\":" + by + ",\"order_by\":[{\"at\":\"asc\"}]}"),
      events(open=true),
      limits(),
    ).unwrap()
    guard @event_typing.options(checked) is Dedupe(spec) else {
      abort("dedupe")
    }
    let keys = @event_typing.dedupe_keys(spec)
    let count = keys.length()
    assert_eq(count, if by == "[]" { 0 } else { 2 })
    keys.clear()
    assert_eq(@event_typing.dedupe_keys(spec).length(), count)
    let order = @event_typing.dedupe_order(spec)
    assert_eq(order[0].field, @row.Unqualified("at"))
    assert_eq(order[0].nulls, @order.Last)
    order.clear()
    assert_eq(@event_typing.dedupe_order(spec).length(), 1)
    assert_true(
      @event_typing.pending_validations(checked).contains(FailOnTopTie),
    )
    assert_true(
      !@event_typing.pending_validations(checked).contains(
        WatermarkClassification,
      ),
    )
    guard @event_typing.output(checked) is @carrier.EventValue(e) else {
      abort("events")
    }
    assert_eq(@carrier.field_set(e.records), @carrier.Open)
    assert_eq(@carrier.field_count(e.records), 3)
  }
}

///|
test "dedupe validates referenced evidence and preserves failure locations" {
  let issue = @event_typing.check_dedupe(
    cursor("{\"by\":[\"payload\"],\"order_by\":[{\"at\":\"asc\"}]}"),
    events(),
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, @event_typing.UnknownFieldType("payload"))
  assert_eq(issue.path, [@source.Key("by"), @source.Index(0)])
  for
    body in [
      "{\"by\":[],\"order_by\":[]}", "{\"by\":[],\"order_by\":[{\"field\":\"at\",\"dir\":\"asc\"}]}",
      "{\"by\":[\"missing\"],\"order_by\":[{\"at\":\"asc\"}]}", "{\"by\":[],\"order_by\":[{\"at\":\"asc\"}],\"keep\":\"first\"}",
    ] {
    assert_true(
      @event_typing.check_dedupe(cursor(body), events(), limits()) is Err(_),
    )
  }
  let source = cursor("{\"by\":[\"event\"],\"order_by\":[{\"at\":\"asc\"}]}")
  let checked = @event_typing.check_dedupe(source, events(), limits()).unwrap()
  let used = @event_typing.usage(checked)
  let cap = limits()
  let exact : @event_typing.Limits = {
    ..cap,
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(@event_typing.check_dedupe(source, events(), exact) is Ok(_))
  for
    caps in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(@event_typing.check_dedupe(source, events(), caps) is Err(_))
  }
}
