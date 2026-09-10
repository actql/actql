///|
test "watermark events retain window evidence into relation grouping and branches" {
  for policy in ["mark", "drop"] {
    let body = cursor(
      "[{\"window_events\":{\"kind\":\"fixed\",\"size\":10},\"as\":\"windowed\"},{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"" +
      policy +
      "\"}},{\"events\":true},{\"window_group\":{\"by\":[],\"aggregates\":{}}},{\"watermark_events\":{\"watermark_ms\":1,\"policy\":\"mark\"},\"from\":\"windowed\"}]",
    )
    let p = @pipeline_typing.check_carriers(
      body,
      [("input", event_input())],
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(p, 1).unwrap()
    assert_true(step.operation is Event(_))
    assert_true(@pipeline_typing.window_evidence(step) is Some(_))
    assert_true(
      @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 3).unwrap())
      is Some(_),
    )
    assert_eq(
      @pipeline_typing.input_occurrences(
        @pipeline_typing.step_at(p, 4).unwrap(),
      )[0].target,
      Step(0),
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
        { ..exact, max_work: used.work - 1, },
        { ..exact, max_nodes: used.nodes - 1, },
        { ..exact, max_text_bytes: used.text_bytes - 1, },
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
}

///|
test "event option diagnostics survive pipeline wrapping" {
  let issue = @pipeline_typing.check_carriers(
    cursor("[{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"other\"}}]"),
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.path, [
    @source.Index(0),
    @source.Key("watermark_events"),
    @source.Key("policy"),
  ])
  assert_true(issue.kind is Event(InvalidBody))
}
