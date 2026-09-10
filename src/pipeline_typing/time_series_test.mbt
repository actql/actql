///|
test "time series generators need no input and feed typed relation consumers" {
  let body = cursor(
    "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":\"1s\"},\"as\":\"grid\"},{\"select\":[\"time\"]}]",
  )
  let p = @pipeline_typing.check_carriers(body, [], None, None, limits()).unwrap()
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(step.input is None)
  assert_true(step.operation is TimeSeries(_))
  assert_true(@pipeline_typing.input_occurrences(step).is_empty())
  assert_eq(@pipeline_typing.lookup(p, "grid"), Some(Step(0)))
  assert_true(
    @schema.lookup(
      @pipeline_typing.output_schema(p).unwrap(),
      Unqualified("time"),
    ).unwrap().shape
    is Timestamp,
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
    @pipeline_typing.check_carriers(body, [], None, None, exact) is Ok(_),
  )
  for
    caps in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(body, [], None, None, caps) is Err(_),
    )
  }
}

///|
test "time series enforces generator alias and from boundaries" {
  let config = "\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":1}"
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{" + config + "}]"),
      [],
      None,
      None,
      limits(),
    )
    is Err({ kind: GeneratorRequiresAlias, .. }),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{" + config + ",\"as\":\"grid\",\"from\":\"input\"}]"),
      [("input", event_input())],
      None,
      None,
      limits(),
    )
    is Err({ kind: GeneratorFrom, .. }),
  )
}
