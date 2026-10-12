///|
test "P2 window calls separate time FieldRefs from durations enums and Parameters" {
  let call = parse_sga_call(
    "row_window(time: r.OCCURRED_MS, kind: 'fixed', size: '10ms', step: @p, offset: -2)",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments, [
    ("time", FieldReference([{value:"r",quoted:false}, {value:"OCCURRED_MS",quoted:false}])),
    ("kind", TextValue("fixed")),
    ("size", TextValue("10ms")),
    ("step", ParameterValue("p")),
    ("offset", NumberValue("-2")),
  ])
  assert_eq(parse_sga_call("watermark_events(watermark_ms: -0.5, policy: 'MARK')", query_limits()).unwrap().arguments,
    [("watermark_ms", NumberValue("-0.5")), ("policy", TextValue("MARK"))])
}

///|
test "P2 window roles reject field Strings and bare enum reinterpretation" {
  for text in [
    "row_window(time: 'occurred_ms', kind: 'fixed', size: 10)",
    "row_window(time: occurred_ms, kind: fixed, size: 10)",
    "window_events(kind: 'fixed', size: 10ms)",
    "watermark_events(watermark_ms: 0, policy: mark)",
  ] {
    assert_true(parse_sga_call(text, query_limits()) is Err(_), msg=text)
  }
}
