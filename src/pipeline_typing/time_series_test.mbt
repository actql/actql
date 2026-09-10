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
test "time series keys retain the generator through calendar aliases and as-of completion" {
  let source = cursor(
    "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":3},\"as\":\"grid\"},{\"calendar_bucket\":{\"time\":\"time\",\"into\":\"bucket\",\"unit\":\"day\",\"timezone\":\"UTC\"}},{\"rename\":{\"time\":\"begin\"}},{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"begin\",\"right_time\":\"at\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"begin\":\"left.begin\"}}}]",
  )
  let p = @pipeline_typing.check_carriers(
    source,
    [("r", calendar_scored_rows())],
    None,
    None,
    limits(),
    calendar_profile=Some(calendar_profile()),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 3).unwrap().operation
    is AsOfJoin(checked~, ..) else {
    abort("as-of")
  }
  assert_eq(@join.asof_identity(checked), [Unqualified("begin")])
  let key = @join.asof_key_completion(checked, Left).unwrap()
  assert_eq(@evidence.key_origin(key), TimeSeriesResult)
  let producer = @evidence.key_time_series_producer(key).unwrap()
  assert_eq(@series.known_row_count(producer), Some(4L))
  assert_eq(
    @evidence.declared_key_field_at(key, 0).unwrap().name,
    Unqualified("time"),
  )
  assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
  assert_true(@evidence.key_calendar_producer(key) is None)
  let caps : @evidence.TransferLimits = { max_work: 2, max_name_bytes: 4, }
  assert_true(@evidence.time_series_keys(producer, caps) is Ok(_))
  assert_true(
    @evidence.time_series_keys(producer, { ..caps, max_work: 1, })
    is Err({ kind: LimitExceeded, .. }),
  )
  assert_true(
    @evidence.time_series_keys(producer, { ..caps, max_name_bytes: 3, })
    is Err({ kind: LimitExceeded, .. }),
  )
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
