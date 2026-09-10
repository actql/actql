///|
test "event dedupe retains window boundaries into grouping with cumulative budgets" {
  for by in ["[]", "[\"id\",\"id\"]"] {
    let source = cursor(
      "[{\"window_events\":{\"kind\":\"fixed\",\"size\":10}},{\"dedupe_events\":{\"by\":" +
      by +
      ",\"order_by\":[{\"at\":\"asc\"}]}},{\"events\":true},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
    )
    let p = @pipeline_typing.check_carriers(
      source,
      [("input", event_input())],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(
      @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 1).unwrap())
      is Some(_),
    )
    assert_eq(
      @schema.field_count(@pipeline_typing.output_schema(p).unwrap()),
      2,
    )
    let used = @pipeline_typing.usage(p)
    let cap = limits()
    let exact : @pipeline_typing.Limits = {
      ..cap,
      max_work: used.work,
      max_nodes: used.nodes,
      max_text_bytes: used.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(
        source,
        [("input", event_input())],
        None,
        None,
        exact,
      )
      is Ok(_),
    )
    for
      caps in [
        { ..exact, max_work: used.work - 1, },
        { ..exact, max_nodes: used.nodes - 1, },
        { ..exact, max_text_bytes: used.text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_carriers(
          source,
          [("input", event_input())],
          None,
          None,
          caps,
        )
        is Err(_),
      )
    }
  }
}

///|
test "event dedupe rejects unknown references with exact pipeline paths" {
  let issue = @pipeline_typing.check_carriers(
    cursor(
      "[{\"dedupe_events\":{\"by\":[\"missing\"],\"order_by\":[{\"at\":\"asc\"}]}}]",
    ),
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_true(issue.kind is Event(UnknownField("missing")))
  assert_eq(issue.path, [
    @source.Index(0),
    @source.Key("dedupe_events"),
    @source.Key("by"),
    @source.Index(0),
  ])
}
